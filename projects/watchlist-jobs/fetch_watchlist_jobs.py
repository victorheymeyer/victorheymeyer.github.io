# projects/watchlist-jobs/fetch_watchlist_jobs.py
import hashlib
import html as html_mod
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

import psycopg2
from psycopg2 import sql as pg_sql

from ats_scrapers.scrapers import GreenhouseScraper, AshbyScraper, AmazonScraper, AppleScraper, GoogleScraper, TikTokScraper, UberScraper, EightfoldScraper, LeverScraper, WorkdayScraper, WorkableScraper, SmartRecruitersScraper, RipplingScraper
from capture_table_stats import TARGETS as STATS_TARGETS
from supabase import create_client

# The site's audience is Seattle-area jobs, so a "day" of postings is a Seattle
# calendar day, not a UTC one. Seattle sits 7-8 hours behind UTC, so any run
# landing in UTC's early morning is still the previous Seattle evening --
# bucketing by UTC date would let one Seattle day split across two snapshots.
SEATTLE_TZ = ZoneInfo("America/Los_Angeles")

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# Direct (non-PostgREST) connection, needed only for VACUUM: it cannot run
# inside a transaction, and every supabase-py call -- including .rpc() --
# is wrapped in one by PostgREST. Optional on purpose: the daily pg_cron
# VACUUM FULL + nightly fallback (see vacuum_full_fallback) still cover
# reclaim if this secret is unset or the connection fails, so a loader run
# should never fail over this.
JOBS_SUPABASE_DB_URL = os.environ.get("JOBS_SUPABASE_DB_URL")


def vacuum_full(table_name):
    """VACUUM FULL + VACUUM a table right after the loader finishes writing
    it, so reclaim happens whenever a run actually completes instead of
    waiting for a fixed daily cron slot -- see the 2026-07-29 conversation
    where a same-day retry's bloat sat unreclaimed for ~10 hours."""
    if not JOBS_SUPABASE_DB_URL:
        print(f"WARNING: JOBS_SUPABASE_DB_URL not set, skipping VACUUM of {table_name}")
        return
    conn = None
    try:
        conn = psycopg2.connect(JOBS_SUPABASE_DB_URL)
        conn.autocommit = True
        # No `with conn:` here -- that's psycopg2's transaction-wrapper
        # context manager (commit/rollback on exit), and pairing it with
        # autocommit mode is exactly what produced "VACUUM cannot run
        # inside a transaction block" on the first live test of this.
        cur = conn.cursor()
        cur.execute(pg_sql.SQL("VACUUM FULL public.{}").format(pg_sql.Identifier(table_name)))
        cur.execute(pg_sql.SQL("VACUUM public.{}").format(pg_sql.Identifier(table_name)))
        cur.close()
        print(f"  VACUUM FULL + VACUUM done for {table_name}")
    except Exception as e:
        print(f"WARNING: failed to vacuum {table_name}: {type(e).__name__}: {e}")
    finally:
        if conn is not None:
            conn.close()

SCRAPERS = {
    "greenhouse": GreenhouseScraper,
    "ashby": AshbyScraper,
    "amazon": AmazonScraper,
    "apple": AppleScraper,
    "google": GoogleScraper,
    "tiktok": TikTokScraper,
    "uber": UberScraper,
    "eightfold": EightfoldScraper,
    "lever": LeverScraper,
    "workday": WorkdayScraper,
    "workable": WorkableScraper,
    "smartrecruiters": SmartRecruitersScraper,
    "rippling": RipplingScraper,
}

# --- Description fingerprint (hash re-anchoring) ------------------------------
# The hash that gates the LLM scoring pipeline must not be a field a third
# party defines. ats-scrapers decides the shape of Job.description on its own
# terms (HTML for Greenhouse, HTML-preferred for Ashby, plain text for others)
# and that shape already moved once across a version bump -- jobhive-py 0.1.0
# gave Greenhouse/Ashby as stripped plain text; ats-scrapers 0.2.0 gives HTML.
# Hashing description_fingerprint()'s output instead of the raw field means a
# future upstream formatting change can't silently rewrite every hash again.
#
# Storage of job_content.description is unchanged: raw HTML still goes in.
# Only the hash input changes.

HASH_ALGO = "plain-v1"

# A handful of company pulls failing per run is normal Workday/ATS flakiness
# (different tenants trip on different days, always recover on their own --
# see e.g. seattlechildrens__external, itron__itron, vantagedc__vantage).
# Only fail the whole run loud when failures look like a systemic outage
# rather than a couple of unlucky tenants.
MAX_TOLERATED_FAILURES = 10

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def description_fingerprint(value):
    """Deterministic plain-text projection used ONLY for change detection.

    Strip tags first so escaped angle brackets survive as literal text, then
    unescape entities, then collapse all whitespace. Dependency-free on
    purpose: pulling in html2text would reintroduce the exact class of
    upstream-drift problem this is fixing.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    text = _TAG_RE.sub(" ", value)
    text = html_mod.unescape(text)
    text = _WS_RE.sub(" ", text).strip()
    return text or None
# -----------------------------------------------------------------------------

# --- Location augmentation (fold secondary locations into Job.location) ------
# refresh_location_flags() (the SQL classifier) only ever inspects the single
# `location` column, but several ATSes report a multi-location posting as one
# primary Job.location string plus the alternates tucked away in Job.raw:
#   - Lever:       raw["categories"]["allLocations"] (list of strings)
#   - Ashby:       raw["secondary_locations"] (list of strings)
#   - Greenhouse:  raw["offices"] (list of office-name strings)
#   - Workable:    raw["locations"] (list of {city, region, country} dicts) --
#     the scraper's own location field only ever takes locations[0]
# A posting whose only Seattle/remote-WA location is one of these alternates
# was invisible to the classifier and silently dropped, e.g. a Wealthfront
# Lever posting listing "Palo Alto, CA (Open to US-based Remote)" primary
# with "Seattle, WA" only in allLocations. Workday already resolves this
# itself (_format_locations) and SmartRecruiters doesn't carry a secondary
# list, so both are left alone here.
def _location_alternates(raw):
    if not isinstance(raw, dict):
        return []
    alternates = []

    categories = raw.get("categories")
    if isinstance(categories, dict):
        for loc in categories.get("allLocations") or []:
            if isinstance(loc, str) and loc.strip():
                alternates.append(loc.strip())

    for loc in raw.get("secondary_locations") or []:
        if isinstance(loc, str) and loc.strip():
            alternates.append(loc.strip())

    for office in raw.get("offices") or []:
        if isinstance(office, str) and office.strip():
            alternates.append(office.strip())

    for loc in raw.get("locations") or []:
        if isinstance(loc, dict):
            parts = [loc.get("city"), loc.get("region"), loc.get("country")]
            joined = ", ".join(p for p in parts if isinstance(p, str) and p.strip())
            if joined:
                alternates.append(joined)
        elif isinstance(loc, str) and loc.strip():
            alternates.append(loc.strip())

    return alternates


def augment_location(location, raw):
    """Append any ATS-captured alternate locations not already present in
    `location`, de-duplicating case-insensitively. Joined with "; " so the
    classifier's existing ";"/"|" segment-splitting logic keeps working."""
    alternates = _location_alternates(raw)
    if not alternates:
        return location
    seen = set()
    parts = []
    for loc in ([location] if location else []) + alternates:
        key = loc.strip().lower()
        if key and key not in seen:
            seen.add(key)
            parts.append(loc)
    return "; ".join(parts) if parts else location
# -----------------------------------------------------------------------------

# --- Workday location-rollup resolution (loader-side, url-only) --------------
# Workday's search endpoint sometimes reports a multi-office posting as a
# rollup string like "5 Locations" instead of the real city list -- the
# actual locations only exist on the per-job CXS detail endpoint. ats-scrapers
# already resolves this during the original scrape (workday.py's
# `_enrich_details`), but a rollup that's still unresolved by the time a row
# reaches job_content stays "N Locations" forever, since nothing re-visits it
# on a later run.
#
# This pass re-fetches just those detail pages, entirely from each row's own
# stored `url` -- confirmed against one stuck row per tenant across all 14
# Workday tenants carrying rollups (cisco, blueorigin, salesforce, adobe, hp,
# crowdstrike, boeing, workday, visa, cloudera, nordstrom, tempus, sprinklr,
# plugpower) that `url` is always the `/job/{location-slug}/{title}_{reqid}`
# shape, never the bare careers URL, so `co`/`site`/`externalPath` are always
# recoverable without touching the vendored scraper or its config.
#
# Deliberately does not import or call into ats_scrapers for any of this: the
# URL-parsing and location-formatting logic below are loader-side
# re-derivations of the same string transforms workday.py does internally,
# not calls into it.
_WORKDAY_ROLLUP_RE = re.compile(r"^\d+\s+Locations?$")
_WORKDAY_JOB_PATH_RE = re.compile(r"/job/.*$")
_WORKDAY_RETRY_STATUSES = {403, 429, 502, 503, 504}
_WORKDAY_MAX_RETRIES = 3
_WORKDAY_RETRY_BACKOFF = 1.5
_WORKDAY_MAX_WORKERS = 8  # kept low on purpose -- Workday 403s on bursts,
                          # which is exactly the failure mode being retried.


def _workday_detail_url(url):
    """Turn a stored Workday job `url` into its CXS detail URL.

    Mirrors workday.py's URL_PATTERN + `_external_path()` (co = first host
    label, site = first path segment, externalPath = from `/job/` on), but
    re-parses the string already sitting in the row rather than calling into
    the scraper. Returns None for anything that doesn't fit the shape --
    no `/job/` segment, or an extra path segment before it (e.g. a locale
    prefix) -- so callers skip the row instead of guessing at a URL shape
    that wasn't verified. (Checked against all 14 tenants: none currently
    need this fallback.)
    """
    parts = urlsplit(url)
    if not parts.netloc or not parts.path:
        return None
    job_match = _WORKDAY_JOB_PATH_RE.search(parts.path)
    if not job_match:
        return None
    external_path = job_match.group(0)
    site_segments = [s for s in parts.path[:job_match.start()].split("/") if s]
    if len(site_segments) != 1:
        return None
    site = site_segments[0]
    co = parts.netloc.split(".")[0]
    return f"https://{parts.netloc}/wday/cxs/{co}/{site}{external_path}"


def _workday_get_detail(detail_url):
    """GET one Workday CXS detail JSON, retrying transient/burst failures.

    A dedicated getter rather than a shared one: this file has no existing
    `_get_with_retry` to extend, so writing a separate function here is what
    keeps every other ATS path (Ashby included) byte-for-byte untouched.
    Accept-only header -- a Content-Type on this GET gets a 406 from
    Workday's CXS endpoint. 403 is retried alongside 429/502/503/504 because
    Workday bursts 403s under concurrency (workday.py's own `_request` does
    the same retry).
    """
    req = urllib.request.Request(
        detail_url,
        headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"},
    )
    last_exc = None
    for attempt in range(_WORKDAY_MAX_RETRIES):
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            if e.code not in _WORKDAY_RETRY_STATUSES or attempt == _WORKDAY_MAX_RETRIES - 1:
                raise
            last_exc = e
        except urllib.error.URLError as e:
            if attempt == _WORKDAY_MAX_RETRIES - 1:
                raise
            last_exc = e
        time.sleep(_WORKDAY_RETRY_BACKOFF ** attempt)
    raise last_exc


def _workday_status_label(exc):
    """Best-effort status label for logging an `_workday_get_detail` failure:
    the HTTP status code when the failure was an HTTP response, else the
    exception's type name. Distinguishing e.g. 403 (IP/burst blocked) from
    404 (bad URL construction) from a bare timeout is the whole point --
    they call for completely different fixes, and collapsing them into one
    error string hides which one happened."""
    if isinstance(exc, urllib.error.HTTPError):
        return str(exc.code)
    return type(exc).__name__


def _workday_format_locations(primary, additional):
    """Loader-side copy of ats_scrapers' workday.py `_format_locations`
    (vendored wheel, ~lines 565-575): pipe-join primary + additional,
    case-sensitive-string dedup. Duplicated rather than imported -- reaching
    into the vendored wheel's internals is off the table, and a copy means a
    future upstream format change won't silently change this pass's output
    without a matching update here.
    """
    locs = []
    if isinstance(primary, str) and primary.strip():
        locs.append(primary.strip())
    if isinstance(additional, list):
        for v in additional:
            if isinstance(v, str) and v.strip() and v.strip() not in locs:
                locs.append(v.strip())
    return " | ".join(locs) if locs else None


# ==============================================================================
# TEMPORARY -- WORKDAY_ROLLUP_DIAGNOSTIC mode.
#
# One-question diagnostic: does the GitHub Actions runner's IP get 403'd by
# Workday under concurrency the way Colab's did? Sample-and-log only, no
# writes to fact_rows/dim_rows or the database. Opt-in via the
# WORKDAY_ROLLUP_DIAGNOSTIC env var (row count, e.g. "20") -- unset, this
# whole block is dead code and `resolve_workday_rollups` behaves exactly as
# before.
#
# TO REMOVE once answered: delete this marked block (both functions) and the
# two marked snippets inside `resolve_workday_rollups` below (the env-var
# read at the top, and the `if diagnostic_n:` branch right after `stuck` is
# built). Nothing else references these names.
# ==============================================================================

def _sample_one_per_company(rows, n):
    """Pick up to n rows spread across distinct companies: one per company
    first (in `rows` order), then fill any remainder from what's left,
    order preserved throughout. Plain list rows, no sorting/shuffling."""
    by_company = {}
    for row in rows:
        by_company.setdefault(row["watchlist_company"], []).append(row)

    sample = [company_rows[0] for company_rows in by_company.values()][:n]
    if len(sample) < n:
        picked = {(r["watchlist_company"], r["ats_id"]) for r in sample}
        for row in rows:
            if len(sample) >= n:
                break
            key = (row["watchlist_company"], row["ats_id"])
            if key not in picked:
                sample.append(row)
                picked.add(key)
    return sample[:n]


def _run_workday_rollup_diagnostic(stuck, n):
    """Fetch+log only: sample up to n stuck rows (one-per-company where
    possible), hit the same detail endpoint the real pass would, and print
    the company / detail URL / outcome for each -- then a status-code
    summary and the resolved strings for anything that succeeded. Never
    touches fact_rows/dim_rows and performs no database I/O of any kind."""
    sample = _sample_one_per_company(stuck, n)
    companies = {r["watchlist_company"] for r in sample}
    print(f"[workday-diagnostic] WORKDAY_ROLLUP_DIAGNOSTIC={n}: sampling "
          f"{len(sample)}/{len(stuck)} stuck rows across {len(companies)} "
          f"companies. Read-only -- nothing will be written.")

    status_counts = {}
    resolved_preview = []

    def probe_one(row):
        company, ats_id, url = row["watchlist_company"], row["ats_id"], row.get("url")
        if not url:
            return company, ats_id, url, None, "NO_URL", None
        detail_url = _workday_detail_url(url)
        if detail_url is None:
            return company, ats_id, url, None, "BAD_URL_SHAPE", None
        try:
            payload = _workday_get_detail(detail_url)
        except Exception as e:
            return company, ats_id, url, detail_url, _workday_status_label(e), None
        jpi = payload.get("jobPostingInfo") or {}
        location = _workday_format_locations(jpi.get("location"), jpi.get("additionalLocations"))
        return company, ats_id, url, detail_url, "200", location

    with ThreadPoolExecutor(max_workers=_WORKDAY_MAX_WORKERS) as pool:
        futures = [pool.submit(probe_one, row) for row in sample]
        for future in as_completed(futures):
            company, ats_id, url, detail_url, status, location = future.result()
            print(f"[workday-diagnostic] {company} | {url} | "
                  f"{detail_url or '(not constructed)'} | status={status}")
            status_counts[status] = status_counts.get(status, 0) + 1
            if location:
                resolved_preview.append((company, ats_id, location))

    counts_str = ", ".join(f"{k}: {v}" for k, v in sorted(status_counts.items()))
    print(f"[workday-diagnostic] summary -- {counts_str}")
    if resolved_preview:
        print("[workday-diagnostic] resolved locations (NOT applied, read-only):")
        for company, ats_id, location in resolved_preview:
            print(f"  {company}/{ats_id}: {location}")
    print("[workday-diagnostic] done -- no fact_rows/dim_rows mutation, no DB writes.")
# ==============================================================================
# END TEMPORARY -- WORKDAY_ROLLUP_DIAGNOSTIC mode (see markers below too).
# ==============================================================================


def resolve_workday_rollups(fact_rows, dim_rows):
    """Resolve Workday "N Locations" rollups to real cities using each
    row's own stored `url`, and apply the result to `fact_rows`/`dim_rows`
    in place.

    Must run before `refresh_location_flags`: that RPC classifies WA /
    remote-WA purely from the `location` text, and a rollup string never
    contains a place name, so an unresolved row can never flag correctly no
    matter where its real locations are -- resolving first is what lets a
    genuinely-Seattle rollup flag on the same run it's found.

    Expected to run after both dedupe() calls, so each (watchlist_company,
    ats_id) is visited once. Non-fatal throughout: every failure is caught,
    logged, and left as "N Locations" to retry next run -- this function
    must never raise past its own boundary or call sys.exit. Self-limiting:
    a row that resolves stops matching `_WORKDAY_ROLLUP_RE`, so this pass's
    own workload shrinks on every run that makes progress.
    """
    # TEMPORARY (WORKDAY_ROLLUP_DIAGNOSTIC) -- read the opt-in env var here;
    # remove this line when ripping out the diagnostic block above.
    diagnostic_n = os.environ.get("WORKDAY_ROLLUP_DIAGNOSTIC")

    stuck = [
        d for d in dim_rows
        if d.get("ats_type") == "workday"
        and isinstance(d.get("location"), str)
        and _WORKDAY_ROLLUP_RE.match(d["location"])
    ]
    if not stuck:
        return

    # TEMPORARY (WORKDAY_ROLLUP_DIAGNOSTIC) -- sample-and-log, then return
    # before any mutation. Remove this whole `if` when ripping out the
    # diagnostic block above.
    if diagnostic_n:
        try:
            diagnostic_n = int(diagnostic_n)
        except ValueError:
            print(f"WARN: WORKDAY_ROLLUP_DIAGNOSTIC={diagnostic_n!r} is not "
                  f"an integer, ignoring it and running normally.")
            diagnostic_n = None
    if diagnostic_n:
        _run_workday_rollup_diagnostic(stuck, diagnostic_n)
        return

    print(f"Resolving {len(stuck)} Workday location rollups...")

    def resolve_one(row):
        key = (row["watchlist_company"], row["ats_id"])
        try:
            url = row.get("url")
            if not url:
                return key, None
            detail_url = _workday_detail_url(url)
            if detail_url is None:
                print(f"  WARN {key[0]}/{key[1]}: url doesn't fit the expected "
                      f"Workday job-path shape, skipping: {url!r}")
                return key, None
            payload = _workday_get_detail(detail_url)
            jpi = payload.get("jobPostingInfo") or {}
            location = _workday_format_locations(
                jpi.get("location"), jpi.get("additionalLocations")
            )
            if not location or _WORKDAY_ROLLUP_RE.match(location):
                return key, None
            return key, location
        except Exception as e:
            print(f"  WARN {key[0]}/{key[1]}: detail fetch failed "
                  f"(status={_workday_status_label(e)}), leaving unresolved: {e}")
            return key, None

    resolved = {}
    with ThreadPoolExecutor(max_workers=_WORKDAY_MAX_WORKERS) as pool:
        futures = [pool.submit(resolve_one, row) for row in stuck]
        for future in as_completed(futures):
            key, location = future.result()
            if location:
                resolved[key] = location

    if not resolved:
        print(f"  resolved 0/{len(stuck)} (all failed or still rolled up)")
        return

    for row in fact_rows:
        key = (row["watchlist_company"], row["ats_id"])
        if key in resolved:
            row["location"] = resolved[key]
    for row in dim_rows:
        key = (row["watchlist_company"], row["ats_id"])
        if key in resolved:
            row["location"] = resolved[key]

    print(f"  resolved {len(resolved)}/{len(stuck)} "
          f"({len(stuck) - len(resolved)} unresolved, retry next run)")
# -----------------------------------------------------------------------------

# --- Area classification (v6 - inside Title_Role_Rules_v7) -----------------------------------
# V6: Split Project/Program Management into separate Program Management and
#     Project Management areas (mirrors the Program Manager / Project
#     Manager role split in ROLE_RULES).
# V5: Added Communications and removed some of the Marketing rules into Comms
# V4: Below
# Maps a job title to one of 25 areas (craft/training, not org unit).
# Ordered rules, first match wins: specific/technical craft is matched before
# broad seniority words; Engineering (engineer/architect) precedes the
# blue-collar buckets; two late catch-alls ("analyst" -> Data & Analytics,
# "specialist" -> Customer Success) only fire when nothing domain-specific hit.
# Re-run every load so rule changes self-heal existing rows on the next pull.

_AREA_RULES = [
    ("Communications", r"\b(communications|\bcomms\b|public relations|\bpr\b|media relations|press secretary|press officer|publicist|spokesperson|speechwriter|public affairs|corporate affairs)\b", r"\bengineer\b|engineering manager|engineering lead|telecommunications|unified communications|solutions architect|communications security|data analyst|brand design|program manager|project manager|product manager"),
    ("Engineering", r"\b(engineer|engineering|architect|developer|\bsre\b|devops|firmware|technical lead|software|\bswe\b|penetration tester|propulsion analyst|thermal analyst)\b", None),
    ("Research", r"\b(research scientist|research engineer|researcher|applied scientist|research fellow|research intern|research lead|research manager|economist|ml researcher|ai researcher|machine learning researcher|postdoc|quantitative researcher|psychologist|fellows program|frontier agents intern)\b", None),
    ("Data & Analytics", r"\b(data analyst|business intelligence|bi analyst|analytics|data scientist|data science|business analyst|product analyst|digital analyst|insights|competitive intelligence|market intelligence|data quality)\b", None),
    ("Product Management", r"\b(product manager|product management|group product manager|director of product|product director|head of product|product owner|product lead)\b", None),
    ("Program Management", r"\b(program manager|technical program|tpm|program director)\b", None),
    ("Project Management", r"\b(project manager|project lead|delivery manager|scrum master|scheduler|special projects manager|project planner)\b", None),
    ("Design", r"\b(designer|design|\bux\b|\bui\b|user experience|creative director|creative lead|art director|motion graphics|graphic)\b", None),
    ("IT / Infrastructure", r"\b(data center|datacenter|it support|it network|it systems|systems administrator|network administrator|network infrastructure|help desk|helpdesk|it helpdesk|technology partner|desktop support|site reliability lead)\b", None),
    ("Security", r"\b(security analyst|security operator|security officer|soc analyst|threat|cyber|cybersecurity|information security|infosec|insider risk|physical security|security risk|incident response|security operations|comsec|security controls|security hardware|identity & access|iam\b)\b", None),
    ("Safety / EHS", r"\b(environmental health|health & safety|health and safety|\behs\b|industrial hygienist|safety specialist|specialist, safety|safety support|environmental specialist)\b", None),
    ("Quality / Inspection", r"\b(quality inspector|quality specialist|nde inspector|\bndt\b|\bnde\b|inspector|quality assurance|\bqa\b|precision inspector|welding inspector|quality control)\b", None),
    ("Skilled Trades", r"\b(welder|welding|machinist|\bcnc\b|\bedm\b|electrician|\bhvac\b|plumber|technician|mechanic|maintenance|fabricator|fabrication|tube bender|foreman|superintendent|journeyman|diamond turning|tool & die|tool and die|cmm programmer|driver)\b", r"data center technician|network|it support|it systems"),
    ("Manufacturing / Production", r"\b(production|manufacturing|assembly|build specialist|build supervisor|machine operator|operator|process operator|material handler|automation & controls|integration & test|integration specialist|test specialist|metrology|smt\b|receiving specialist|shipping specialist)\b", None),
    ("Supply Chain / Procurement", r"\b(sourcing|global supply|supply manager|supplier|buyer|procurement|inventory|materials management|purchasing|logistics|supply chain|warehouse|supply materials)\b", None),
    ("Hospitality / Facilities", r"\b(chef|cook|barista|porter|mixologist|food service|hospitality|facilities|janitor|custodian|soft services)\b", None),
    ("Sales", r"\b(sales|account executive|\bae\b|account manager|\bsdr\b|\bbdr\b|sales development|business development|revenue|go.?to.?market|\bgtm\b|partnerships|partner development|partner manager|partner lead|partner specialist|alliance|alliances|channel|account lead|account specialist|renewals|renewal manager|value advisor|relationship manager|market manager|growth lead|growth manager|growth specialist|enterprise\b|market access)\b", None),
    ("Marketing", r"\b(marketing|marketer|\bbrand\b|demand gen|demand generation|growth marketing|content|social media|\bseo\b|\bsem\b|copy|editor|events|campaign|paid media|analyst relations|web producer|photographer|technical writer)\b", None),
    ("Finance", r"\b(finance|financial|accounting|accountant|accounts payable|accounts receivable|controller|fp&a|treasury|audit|auditor|\btax\b|commissions|payroll|underwriter|underwriting|credit|collections|\bloan\b|mortgage|billing|capital markets|controllership|reporting|fraud|pricing|deal desk|deal pricing|investment|investments|liquidity|stock plan|stock administration|transfer pricing|lending)\b", None),
    ("Legal", r"\b(legal|counsel|attorney|paralegal|compliance|privacy|contracts manager|contract manager|contracts negotiator|sanctions|regulatory|immigration|trust & safety)\b", None),
    ("Strategy", r"\b(strategy|strategic|strategist|corporate development|corp dev|\bpolicy\b|government affairs|public policy|government incentives|land acquisition|site selection|real estate|construction manager|campus planning|site expansion)\b", None),
    ("Operations", r"\b(operations|\bops\b|bizops|biz ops|business operations|business process|resource manager|workforce planning|localization|professional services|practice manager)\b", None),
    ("Recruiting / People", r"\b(recruiter|recruiting|talent|\bpeople\b|human resources|\bhr\b|sourcer|benefits|compensation|employee relations|total rewards|candidate specialist|learning|generalist|mobility)\b", None),
    ("Customer Success", r"\b(customer success|customer support|technical account manager|\btam\b|implementation|onboarding|support specialist|consultant|solutions consultant|premium support|product support|client services|member service|escalation|escalations|enablement|delivery success|services solutions|technical solutions|solution specialist|technical delivery|deployment)\b", None),
    ("Administrative", r"\b(executive assistant|administrative|\badmin\b|office manager|receptionist|coordinator|assistant|briefing manager)\b", None),
    ("Data & Analytics", r"\banalyst\b", None),
    ("Customer Success", r"\bspecialist\b", None),
]



_AREA_COMPILED = [
    (d, re.compile(p, re.I), re.compile(n, re.I) if n else None)
    for d, p, n in _AREA_RULES
]


def classify_area(title):
    t = title or ""
    for area, pos, neg in _AREA_COMPILED:
        if pos.search(t) and not (neg and neg.search(t)):
            return area
    return "Other"
# -----------------------------------------------------------------------------

# --- Role classification (Title_Role_Rules v7) -------------------------------
# Maps a job title to a base role archetype using ordered keyword rules,
# first match wins. Each rule has one or two keywords joined by an operator:
#   op == "AND"  -> every keyword must be present
#   op == "OR"   -> any keyword present (also used for single-keyword rules)
# Matching is whole-word and case-insensitive. Ordering matters: compound and
# specific rules sit above broad catch-alls (e.g. Marketing precedes bare
# Market; Program Manager precedes bare Program). Unmatched titles return None
# (stored as NULL) rather than being forced into a catch-all.
# Re-run every load so rule edits self-heal existing rows on the next pull.
#
# v7 change log vs v5: adds ordered Communications rules (director of / head of /
# manager / lead / specialist / reporter) above the generic manager rules, adds a
# Public Relations rule, and adds a Communications (other) catch-all at the end.
#
# Source of truth: Title_Role_Rules_v7.xlsx (sheet 'v7'), regenerated into this
# list via a Colab cell when rules change. Do not hand-edit individual rows here
# without updating the spreadsheet too.

ROLE_RULES = [
    {"order": 1, "role": 'Audit', "op": 'OR', "keywords": ['Audit', 'Auditor']},
    {"order": 2, "role": 'Chief of Staff', "op": None, "keywords": ['Chief of Staff']},
    {"order": 3, "role": 'executive assistant', "op": None, "keywords": ['executive assistant']},
    {"order": 4, "role": 'Account Executive', "op": 'OR', "keywords": ['Account Executive', 'Account Exec']},
    {"order": 5, "role": 'Account Manager', "op": 'OR', "keywords": ['Account Manager', 'Account Mgr']},
    {"order": 6, "role": 'Account Lead/Director', "op": 'OR', "keywords": ['Account Lead', 'Account Director']},
    {"order": 7, "role": 'Product Manager', "op": None, "keywords": ['Product Manager']},
    {"order": 8, "role": 'Program Manager', "op": None, "keywords": ['Program Manager']},
    {"order": 9, "role": 'Project Manager', "op": None, "keywords": ['Project Manager']},
    {"order": 10, "role": 'Relationship Manager', "op": None, "keywords": ['Relationship Manager']},
    {"order": 11, "role": 'Marketing Manager', "op": None, "keywords": ['Marketing Manager']},
    {"order": 12, "role": 'Engineering Manager', "op": None, "keywords": ['Engineering Manager']},
    {"order": 13, "role": 'Engineering Director', "op": None, "keywords": ['Engineering Director']},
    {"order": 14, "role": 'Solutions Architect', "op": None, "keywords": ['Solutions Architect']},
    {"order": 15, "role": 'Data Analyst/Analysis', "op": 'OR', "keywords": ['Data Analyst', 'Data Analysis']},
    {"order": 16, "role": 'Data Scientist/Science', "op": 'OR', "keywords": ['Data Scientist', 'Data Science']},
    {"order": 17, "role": 'operations manager', "op": None, "keywords": ['operations manager']},
    {"order": 18, "role": 'sales manager', "op": None, "keywords": ['sales manager']},
    {"order": 19, "role": 'director of communications', "op": 'OR', "keywords": ['director of communications', 'communications director']},
    {"order": 20, "role": 'head of communications', "op": None, "keywords": ['head of communications']},
    {"order": 21, "role": 'communications manager', "op": None, "keywords": ['communications manager']},
    {"order": 22, "role": 'communications lead', "op": None, "keywords": ['communications lead']},
    {"order": 23, "role": 'communications specialist', "op": None, "keywords": ['communications specialist']},
    {"order": 24, "role": 'communications reporter', "op": None, "keywords": ['communications reporter']},
    {"order": 25, "role": 'supply manager', "op": None, "keywords": ['supply manager']},
    {"order": 26, "role": 'sales specialist', "op": None, "keywords": ['sales specialist']},
    {"order": 27, "role": 'sourcing manager', "op": None, "keywords": ['sourcing manager']},
    {"order": 28, "role": 'finance manager', "op": None, "keywords": ['finance manager']},
    {"order": 29, "role": 'operations associate', "op": None, "keywords": ['operations associate']},
    {"order": 30, "role": 'operations analyst', "op": None, "keywords": ['operations analyst']},
    {"order": 31, "role": 'Engineer', "op": None, "keywords": ['Engineer']},
    {"order": 32, "role": 'Public Relations', "op": None, "keywords": ['Public Relations']},
    {"order": 33, "role": 'counsel', "op": None, "keywords": ['counsel']},
    {"order": 34, "role": 'Product Management', "op": None, "keywords": ['Product Management']},
    {"order": 35, "role": 'Finance & Strategy', "op": 'AND', "keywords": ['Finance', 'Strategy']},
    {"order": 36, "role": 'Strategy & Operations', "op": 'AND', "keywords": ['Strategy', 'Operations']},
    {"order": 37, "role": 'Auditor', "op": None, "keywords": ['Auditor']},
    {"order": 38, "role": 'Designer', "op": None, "keywords": ['Designer']},
    {"order": 39, "role": 'Technician', "op": None, "keywords": ['Technician']},
    {"order": 40, "role": 'Scientist', "op": 'OR', "keywords": ['Scientist', 'Science']},
    {"order": 41, "role": 'Recruiter', "op": 'OR', "keywords": ['Recruiter', 'Recruiting']},
    {"order": 42, "role": 'Architect', "op": None, "keywords": ['Architect']},
    {"order": 43, "role": 'Researcher', "op": None, "keywords": ['Researcher']},
    {"order": 44, "role": 'Accountant/Accounting', "op": 'OR', "keywords": ['Accountant', 'Accounting']},
    {"order": 45, "role": 'Mechanic', "op": None, "keywords": ['Mechanic']},
    {"order": 46, "role": 'Welder', "op": 'OR', "keywords": ['Welder', 'Welding']},
    {"order": 47, "role": 'Driver', "op": None, "keywords": ['Driver']},
    {"order": 48, "role": 'Inspector', "op": None, "keywords": ['Inspector']},
    {"order": 49, "role": 'Economist', "op": None, "keywords": ['Economist']},
    {"order": 50, "role": 'Cook', "op": 'OR', "keywords": ['Cook', 'Chef']},
    {"order": 51, "role": 'Machinist', "op": 'OR', "keywords": ['Machinist', 'Machine Operator']},
    {"order": 52, "role": 'Trainer', "op": None, "keywords": ['Trainer']},
    {"order": 53, "role": 'Business Planner/Planning', "op": 'OR', "keywords": ['Business Planner', 'Business Planning']},
    {"order": 54, "role": 'Consultant', "op": None, "keywords": ['Consultant']},
    {"order": 55, "role": 'Strategist', "op": None, "keywords": ['Strategist']},
    {"order": 56, "role": 'Developer', "op": None, "keywords": ['Developer']},
    {"order": 57, "role": 'Administrator', "op": 'OR', "keywords": ['Admin', 'Administrator']},
    {"order": 58, "role": 'Legal & Counsel', "op": 'OR', "keywords": ['Counsel', 'Legal']},
    {"order": 59, "role": 'Product Strategy', "op": 'AND', "keywords": ['Product', 'Strategy']},
    {"order": 60, "role": 'Strategy', "op": None, "keywords": ['Strategy']},
    {"order": 61, "role": 'Engineering', "op": None, "keywords": ['Engineering']},
    {"order": 62, "role": 'Strategic Finance', "op": None, "keywords": ['Strategic Finance']},
    {"order": 63, "role": 'Corp Dev', "op": None, "keywords": ['Corporate Development']},
    {"order": 64, "role": 'Sales Dev', "op": None, "keywords": ['Sales Development']},
    {"order": 65, "role": 'Biz Dev', "op": None, "keywords": ['Business Development']},
    {"order": 66, "role": 'Customer Success', "op": None, "keywords": ['Customer Success']},
    {"order": 67, "role": 'Customer Support', "op": None, "keywords": ['Customer Support']},
    {"order": 68, "role": 'Marketing', "op": None, "keywords": ['Marketing']},
    {"order": 69, "role": 'Supply Chain', "op": None, "keywords": ['Supply Chain']},
    {"order": 70, "role": 'Delivery Success', "op": None, "keywords": ['Delivery Success']},
    {"order": 71, "role": 'Financial Planning', "op": None, "keywords": ['Financial Planning']},
    {"order": 72, "role": 'Sourcing', "op": None, "keywords": ['Sourcing']},
    {"order": 73, "role": 'Incident', "op": 'OR', "keywords": ['Incident', 'Escalations']},
    {"order": 74, "role": 'Production', "op": 'OR', "keywords": ['Production', 'Manufacturing']},
    {"order": 75, "role": 'Research', "op": None, "keywords": ['Research']},
    {"order": 76, "role": 'People', "op": None, "keywords": ['People']},
    {"order": 77, "role": 'Tax', "op": None, "keywords": ['Tax']},
    {"order": 78, "role": 'Fraud', "op": None, "keywords": ['Fraud']},
    {"order": 79, "role": 'Financing', "op": None, "keywords": ['Financing']},
    {"order": 80, "role": 'Treasury', "op": None, "keywords": ['Treasury']},
    {"order": 81, "role": 'Contract', "op": 'OR', "keywords": ['Contract', 'Contracts']},
    {"order": 82, "role": 'Technical', "op": None, "keywords": ['Technical']},
    {"order": 83, "role": 'Contract Job', "op": None, "keywords": ['(Contract)']},
    {"order": 84, "role": 'Alliance', "op": None, "keywords": ['Alliance']},
    {"order": 85, "role": 'Partnerships', "op": None, "keywords": ['Partnerships']},
    {"order": 86, "role": 'Engagement', "op": None, "keywords": ['Engagement']},
    {"order": 87, "role": 'Enablement', "op": None, "keywords": ['Enablement']},
    {"order": 88, "role": 'Market', "op": None, "keywords": ['Market']},
    {"order": 89, "role": 'Analytics (Other)', "op": None, "keywords": ['Analytics']},
    {"order": 90, "role": 'Finance (Other)', "op": None, "keywords": ['Finance']},
    {"order": 91, "role": 'Analyst (Other)', "op": None, "keywords": ['Analyst']},
    {"order": 92, "role": 'Sales (other)', "op": None, "keywords": ['Sales']},
    {"order": 93, "role": 'GTM (other)', "op": None, "keywords": ['GTM']},
    {"order": 94, "role": 'Operations (other)', "op": None, "keywords": ['Operations']},
    {"order": 95, "role": 'Support (Other)', "op": None, "keywords": ['Support']},
    {"order": 96, "role": 'Program (Other)', "op": None, "keywords": ['Program']},
    {"order": 97, "role": 'Planning (other)', "op": None, "keywords": ['Planning']},
    {"order": 98, "role": 'Design (Other)', "op": None, "keywords": ['Design']},
    {"order": 99, "role": 'Analysis (other)', "op": None, "keywords": ['Analysis']},
    {"order": 100, "role": 'Tech (other)', "op": None, "keywords": ['Tech']},
    {"order": 101, "role": 'Communications (other)', "op": None, "keywords": ['Communications']},
]


# Pre-compile each keyword to a whole-word, case-insensitive pattern once,
# preserving the intended first-match-wins order (by "order" field).
_ROLE_COMPILED = [
    {
        "role": r["role"],
        "op": r["op"],
        "patterns": [
            re.compile(r"\b" + re.escape(str(k).strip()) + r"\b", re.I)
            for k in r["keywords"]
        ],
    }
    for r in sorted(ROLE_RULES, key=lambda x: x["order"])
]


def classify_role(title):
    t = title or ""
    if not t:
        return None
    for rule in _ROLE_COMPILED:
        pats = rule["patterns"]
        if rule["op"] == "AND":
            hit = all(p.search(t) for p in pats)
        else:  # "OR" or single-keyword
            hit = any(p.search(t) for p in pats)
        if hit:
            return rule["role"]
    return None
# -----------------------------------------------------------------------------

# --- Level classification (frozen v1) ----------------------------------------
# Maps a job title to a seniority/level value, an axis independent of
# area and role. Ordered rules, first match wins. Each rule lists one or
# two patterns; multiple patterns must ALL match (AND, used for "Senior +
# word" combos so word order/adjacency doesn't matter). Titles are normalized
# (Sr./Sr/Snr/Snr. -> Senior) before classification, but the normalized string
# is only used for matching, never written back to the stored title. Unmatched
# titles return None (stored as NULL). Re-run every load so rule edits
# self-heal existing rows on the next pull.

_SENIOR_PATTERN = re.compile(r"\b(?:sr|snr)\.?\b", re.IGNORECASE)


def normalize_title_for_level(title):
    if not title:
        return title
    return _SENIOR_PATTERN.sub("Senior", title)


_LEVEL_RULES = [
    ("Chief of Staff",    [r"\b(chief\s+of\s+staff|cos)\b"]),
    ("CXO",              [r"\bchief\b", r"\bofficer\b"]),
    ("VP",                [r"\b(vice\s+president|vp)\b"]),
    ("GM",                [r"\b(general\s+manager|gm)\b"]),
    ("Supervisor",        [r"\bsupervisor\b"]),
    ("Superintendent",    [r"\bsuperintendent\b"]),
    ("Senior Director",   [r"\bsenior\b", r"\bdirector\b"]),
    ("Director",          [r"\b(director|dir\.?)\b"]),
    ("Head of",           [r"\bhead\s+of\b"]),
    ("Senior Principal",  [r"\bsenior\b", r"\bprincipal\b"]),
    ("Principal",         [r"\bprincipal\b"]),
    ("Staff",             [r"\bstaff\b"]),
    ("Lead",              [r"\blead\b"]),
    ("Senior Manager",    [r"\bsenior\b", r"\bmanager\b"]),
    ("Manager",           [r"\b(manager|mgr\.?)\b"]),
    ("Senior Analyst",    [r"\bsenior\b", r"\banalyst\b"]),
    ("Analyst",           [r"\banalyst\b"]),
    ("Senior Associate",  [r"\bsenior\b", r"\bassociate\b"]),
    ("Associate",         [r"\bassociate\b"]),
    ("Specialist",        [r"\bspecialist\b"]),
    ("Coordinator",       [r"\bcoordinator\b"]),
    ("Assistant",         [r"\bassistant\b"]),
    ("Rotation",          [r"\brotation\b"]),
    ("I",                 [r"\bI\b"]),
    ("II",                [r"\bII\b"]),
    ("Senior",            [r"\bsenior\b"]),  # catch-all, must stay last
]
_LEVEL_CASE_SENSITIVE = {"I", "II"}

_LEVEL_COMPILED = [
    (
        name,
        [re.compile(p, 0 if name in _LEVEL_CASE_SENSITIVE else re.IGNORECASE) for p in patterns],
    )
    for name, patterns in _LEVEL_RULES
]


def classify_level(title):
    t = normalize_title_for_level(title)
    if not t:
        return None
    for name, patterns in _LEVEL_COMPILED:
        if all(p.search(t) for p in patterns):
            return name
    return None
# -----------------------------------------------------------------------------

def classify_pull_error(error_message):
    """Map a raw pull error string to (error_code, outcome).
    Buckets drive response: BLOCKED = back off, REMOVED = fix/drop the slug,
    CONFIG = fix watchlist data, ERROR = investigate, TRANSIENT = self-recovers,
    ignore. Matching is substring on the error_message the loop builds
    ("ExceptionType: message"). Order matters: specific before generic.
    """
    m = (error_message or "").lower()
    # --- config / data problems (never hit the network) ---
    if "no scraper" in m or "unknown ats" in m:
        return "CONFIG", "CONFIG"
    if "url must look like" in m:                 # bare Workday tenant/site slug
        return "CONFIG", "CONFIG"
    # --- dead / moved boards ---
    if "companynotfounderror" in m or "not found" in m or " 404" in m:
        return "NOT_FOUND", "REMOVED"
    # --- explicit block signals ---
    if " 429" in m or "too many requests" in m or "rate limit" in m:
        return "RATE_LIMITED", "BLOCKED"
    if "just a moment" in m or "attention required" in m or "cf-" in m or "challenge" in m:
        return "CHALLENGE", "BLOCKED"
    # --- Workday "gave up after N retries" ---
    # Proven transient in testing (recover on retest, not blocks). Treat as
    # TRANSIENT, not BLOCKED, so they don't cry wolf. A real block shows up as
    # 429/challenge above.
    if "gave up after" in m and "retries" in m:
        return "TRANSIENT", "ERROR"
    # --- transport / server ---
    if "timeout" in m or "timed out" in m:
        return "TIMEOUT", "BLOCKED"
    if any(s in m for s in (" 500", " 502", " 503", " 504", "server error")):
        return "SERVER_ERROR", "ERROR"
    if " 403" in m or "forbidden" in m:
        return "FORBIDDEN", "REMOVED"
    return "OTHER", "ERROR"
# -----------------------------------------------------------------------------

snapshot_date = datetime.now(SEATTLE_TZ).date().isoformat()

FACT_COLS = ["snapshot_date", "watchlist_company", "ats_id", "title", "location", "posted_at",
             "description_hash", "hash_algo"]
DIM_COLS = ["watchlist_company", "ats_id", "title", "location", "department", "description",
            "url", "apply_url", "last_seen", "fetched_at", "area", "role_keyword",
            "level", "raw", "description_change_count",
            "description_last_change_chars", "description_plain_len", "requisition_id",
            "ats_type", "is_remote", "team", "employment_type",
            "salary_min", "salary_max", "salary_currency", "salary_period", "posted_at"]

# description_last_change is not tracked here: it duplicated the existing
# current_version_first_seen column (verified byte-identical), which
# refresh_job_freshness() already maintains after every run. Consolidated
# onto that column; the jobs_location_flags view aliases it back to the
# description_last_change name for existing consumers.
CHANGE_STATE_COLS = ["watchlist_company", "ats_id", "current_description_hash",
                      "hash_algo", "description_change_count",
                      "description_last_change_chars", "description_plain_len"]


def load_watchlist():
    """Read active companies from the watchlist_companies table.

    scraper_kwargs is an optional JSONB column for scrapers that need more
    than a bare company_slug (e.g. Eightfold tenants on a custom domain like
    Microsoft, which needs base_url and domain). NULL/empty for every company
    on a default slug-based setup, so this is a no-op for the existing rows.
    """
    resp = sb.table("watchlist_companies") \
        .select("company,ats,slug,scraper_kwargs") \
        .eq("active", True) \
        .order("priority") \
        .execute()
    rows = resp.data or []
    watchlist = [
        {
            "company": r["company"],
            "ats": (r["ats"] or "").lower(),
            "slug": r["slug"],
            "scraper_kwargs": r.get("scraper_kwargs") or {},
        }
        for r in rows
    ]
    if not watchlist:
        print("ERROR: watchlist read returned 0 active companies; aborting "
              "(check the watchlist_companies table and DB connectivity).")
        sys.exit(1)
    return watchlist


def load_pull_successes(snapshot_date):
    """Companies already successfully scraped+upserted for snapshot_date, so
    a same-day retry (of the whole workflow) can skip redoing them instead
    of re-scraping and re-upserting everyone from scratch. See
    pull_successes migration for why this exists."""
    resp = sb.table("pull_successes").select("watchlist_company") \
        .eq("snapshot_date", snapshot_date).execute()
    return {r["watchlist_company"] for r in (resp.data or [])}


def load_change_tracking_state():
    """Bulk pre-read of job_content's change-tracking columns, keyed by
    (watchlist_company, ats_id), so the per-job loop below can tell a real
    description edit from a scraper's null-hash blip without re-deriving
    history from raw_watchlist_jobs (which is pruned to RETENTION_DAYS).

    current_description_hash is job_content's existing "previous hash"
    column, already kept in sync by the refresh_job_freshness RPC after
    every run (it only updates when the day's hash is both present and
    different). Reusing it here avoids tracking the same hash twice.
    hash_algo travels alongside it so the comparison below can tell a
    hashing-algorithm change apart from a real content change.

    Paginated in chunks of 1000, PostgREST's default max rows per request.
    A short final page ends the read; anything else raises rather than
    proceeding on a partial read, since these columns are written back on
    every row of every run (added to DIM_COLS) -- a partial pre-read would
    silently reset the rest of job_content's change-tracking state to
    0/null on the next upsert, with no error surfaced.
    """
    state = {}
    page_size = 1000
    offset = 0
    while True:
        resp = sb.table("job_content").select(",".join(CHANGE_STATE_COLS)) \
            .order("watchlist_company").order("ats_id") \
            .range(offset, offset + page_size - 1).execute()
        rows = resp.data or []
        for r in rows:
            state[(r["watchlist_company"], r["ats_id"])] = r
        if len(rows) < page_size:
            break
        offset += page_size

    expected = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    if len(state) != expected:
        print(f"ERROR: change-tracking pre-read got {len(state)} rows but "
              f"job_content has {expected}; aborting before write to avoid "
              f"resetting change-tracking state for the difference.")
        sys.exit(1)
    return state


ALERT_TO = "red.alert@heymeyer.com"
ALERT_FROM = "Watchlist Monitor <alerts@mail.heymeyer.com>"


def _query_removed_candidates():
    """Companies REMOVED for 5+ consecutive days (safe-to-deactivate list)."""
    try:
        cutoff = (datetime.now(SEATTLE_TZ).date() - timedelta(days=4)).isoformat()
        resp = sb.table("pull_failures") \
            .select("watchlist_company, ats, snapshot_date") \
            .eq("outcome", "REMOVED") \
            .gte("snapshot_date", cutoff) \
            .execute()
        by_co = {}
        for r in (resp.data or []):
            by_co.setdefault((r["watchlist_company"], r["ats"]), set()).add(r["snapshot_date"])
        return sorted([f"{co} ({ats})" for (co, ats), days in by_co.items() if len(days) >= 5])
    except Exception as e:
        print(f"WARNING: removed-candidate query failed: {type(e).__name__}: {e}")
        return []


def _query_repeat_offenders():
    """Non-BLOCKED failures recurring on 3+ distinct days in the last 7."""
    try:
        cutoff = (datetime.now(SEATTLE_TZ).date() - timedelta(days=6)).isoformat()
        resp = sb.table("pull_failures") \
            .select("watchlist_company, ats, outcome, snapshot_date") \
            .neq("outcome", "BLOCKED") \
            .gte("snapshot_date", cutoff) \
            .execute()
        by_co = {}
        for r in (resp.data or []):
            key = (r["watchlist_company"], r["ats"], r["outcome"])
            by_co.setdefault(key, set()).add(r["snapshot_date"])
        return sorted([f"{co} ({ats}, {out}, {len(days)}d)"
                       for (co, ats, out), days in by_co.items() if len(days) >= 3])
    except Exception as e:
        print(f"WARNING: repeat-offender query failed: {type(e).__name__}: {e}")
        return []


def send_alert_email(failure_rows, snapshot_date):
    """Send ONE alert email if anything needs attention; else nothing."""
    blocked = [r for r in failure_rows if r.get("outcome") == "BLOCKED"]
    removed_candidates = _query_removed_candidates()
    repeat_offenders = _query_repeat_offenders()

    # TEMP TEST SCAFFOLDING: fire on any classified failure today. REMOVE after test.
    todays_failures = [r for r in failure_rows if r.get("error_code")]
    
    if not blocked and not removed_candidates and not repeat_offenders and not todays_failures:
        print("Alert email: nothing to report (healthy day), not sending.")
        return

    api_key = os.environ.get("RESEND_API_KEY")
    if not api_key:
        print("WARNING: RESEND_API_KEY not set; skipping alert email.")
        return

    lines = [f"Watchlist pull alert — {snapshot_date}", ""]
    if blocked:
        lines.append(f"[!] BLOCKED today ({len(blocked)}) — investigate:")
        for r in blocked:
            lines.append(f"    - {r['watchlist_company']} ({r['ats']}): "
                         f"{r.get('error_code')} :: {r.get('error_message', '')[:120]}")
        lines.append("")
    if removed_candidates:
        lines.append(f"[x] Dead 5+ days — safe to deactivate ({len(removed_candidates)}):")
        for c in removed_candidates:
            lines.append(f"    - {c}")
        lines.append("")
    if repeat_offenders:
        lines.append(f"[~] Repeat offenders, 3+ days ({len(repeat_offenders)}):")
        for c in repeat_offenders:
            lines.append(f"    - {c}")
        lines.append("")
    # TEMP TEST SCAFFOLDING: remove with the todays_failures block above.
    if todays_failures:
        lines.append(f"[i] All failures today ({len(todays_failures)}):")
        for r in todays_failures:
            lines.append(f"    - {r['watchlist_company']} ({r['ats']}): "
                         f"{r.get('error_code')}/{r.get('outcome')} :: "
                         f"{r.get('error_message', '')[:100]}")
        lines.append("")
    body = "\n".join(lines)

    subject_bits = []
    if blocked:
        subject_bits.append(f"{len(blocked)} BLOCKED")
    if removed_candidates:
        subject_bits.append(f"{len(removed_candidates)} dead")
    if repeat_offenders:
        subject_bits.append(f"{len(repeat_offenders)} repeat")
    if todays_failures and not subject_bits:
        subject_bits.append(f"{len(todays_failures)} failures")
    subject = "Watchlist alert: " + ", ".join(subject_bits)

    payload = json.dumps({
        "from": ALERT_FROM,
        "to": [ALERT_TO],
        "subject": subject,
        "text": body,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "watchlist-alerts/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            print(f"Alert email sent to {ALERT_TO} (HTTP {resp.status}): {subject}")
    except Exception as e:
        # Never let an alert failure break the run.
        print(f"WARNING: alert email failed to send: {type(e).__name__}: {e}")


def main():
    watchlist = load_watchlist()
    print(f"Loaded {len(watchlist)} active companies from watchlist_companies")

    already_done = load_pull_successes(snapshot_date)
    pending = [e for e in watchlist if e["company"] not in already_done]
    if not pending:
        print(f"All {len(watchlist)} companies already loaded for {snapshot_date}; nothing to do.")
        return
    if already_done:
        print(f"{len(already_done)} companies already loaded for {snapshot_date}; "
              f"scraping remaining {len(pending)}")

    change_state = load_change_tracking_state()
    print(f"Pre-read change-tracking state for {len(change_state)} jobs")

    fact_rows, dim_rows = [], []
    failures = []
    failure_rows = []
    success_rows = []

    for entry in pending:
        company, ats, slug = entry["company"], entry["ats"], entry["slug"]
        scraper_kwargs = entry.get("scraper_kwargs") or {}
        if ats not in SCRAPERS:
            print(f"SKIP {company:12s}: unknown ats '{ats}' (no scraper)")
            failures.append(company)
            msg = f"unknown ats '{ats}' (no scraper)"
            code, outcome = classify_pull_error(msg)
            failure_rows.append({
                "snapshot_date": snapshot_date,
                "watchlist_company": company,
                "ats": ats,
                "error_message": msg,
                "error_code": code,
                "outcome": outcome,
            })
            continue
        try:
            jobs = SCRAPERS[ats](slug, **scraper_kwargs).fetch()

            for j in jobs:
                d = j.model_dump(mode="json")
                d["snapshot_date"] = snapshot_date
                d["watchlist_company"] = company
                d["ats_id"] = str(d.get("ats_id"))
                d["last_seen"] = snapshot_date
                d["location"] = augment_location(d.get("location"), d.get("raw"))

                # Hash a normalized plain-text projection of the description
                # (see description_fingerprint above), not the raw field --
                # ats-scrapers decides the raw shape, and that shape already
                # changed once across a version bump.
                raw_description = d.get("description")
                fingerprint = description_fingerprint(raw_description)
                new_hash = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest() if fingerprint else None
                d["description_hash"] = new_hash
                d["hash_algo"] = HASH_ALGO

                # Char-delta change tracking, computed on the fingerprint
                # length rather than the raw stored description's length, so
                # HTML markup weight never registers as a content change.
                # new_hash/new_len are None together whenever today's
                # description came back empty (a scraper miss, e.g.
                # Microsoft's Eightfold capture flakes on ~80% of days) --
                # require new_hash is not None, not just prev_hash, or every
                # such miss would register as a "change" against the last
                # real hash.
                #
                # Algo-aware: if prev_algo doesn't match this run's HASH_ALGO
                # (including every pre-migration row, where hash_algo is
                # still NULL), prev_hash was computed by a different
                # normalizer -- a mismatch there reflects the algorithm
                # switch, not necessarily a content edit, so it must not
                # register as a change. refresh_job_freshness applies the
                # same rule to current_version_first_seen. This is what lets
                # a future algorithm change self-heal on its own next run,
                # with no cutover-night script. Accepted limitation: a
                # genuine content edit landing on the exact same run as an
                # algorithm switch is indistinguishable from the switch
                # itself and gets swallowed -- one run's blind spot, not
                # ongoing.
                new_len = len(fingerprint) if fingerprint else None
                prev = change_state.get((company, d["ats_id"]))
                prev_hash = prev["current_description_hash"] if prev else None
                prev_algo = prev.get("hash_algo") if prev else None

                if prev is None:
                    change_count, last_chars = 0, None
                elif prev_algo != HASH_ALGO:
                    change_count = prev["description_change_count"] or 0
                    last_chars = prev["description_last_change_chars"]
                elif prev_hash is not None and new_hash is not None and new_hash != prev_hash:
                    change_count = (prev["description_change_count"] or 0) + 1
                    prev_len = prev["description_plain_len"]
                    last_chars = (new_len - prev_len) if (new_len is not None and prev_len is not None) else None
                else:
                    change_count = prev["description_change_count"] or 0
                    last_chars = prev["description_last_change_chars"]

                d["description_change_count"] = change_count
                d["description_last_change_chars"] = last_chars
                # Only refresh the length helper when today's text is
                # real; on a null-hash day, keep the last known length
                # so the next real change can still compute a delta.
                d["description_plain_len"] = (
                    new_len if new_len is not None
                    else (prev["description_plain_len"] if prev else None)
                )

                # d["description"] is already what ats-scrapers returned
                # (HTML for Greenhouse, HTML-preferred for Ashby, etc.) --
                # storage-ready natively, no second fetch or html_map merge
                # needed.

                # Classify area from title (frozen v4 rules).
                d["area"] = classify_area(d.get("title"))

                # Classify role archetype from title (Title_Role_Rules v4).
                d["role_keyword"] = classify_role(d.get("title"))

                # Classify seniority level from title (frozen v1 rules).
                d["level"] = classify_level(d.get("title"))

                fact_rows.append({k: d.get(k) for k in FACT_COLS})
                dim_rows.append({k: d.get(k) for k in DIM_COLS})

            print(f"OK   {company:12s} ({ats}/{slug}): {len(jobs)} jobs")
            success_rows.append({
                "snapshot_date": snapshot_date,
                "watchlist_company": company,
                "ats": ats,
                "job_count": len(jobs),
            })
        except Exception as e:
            error_message = f"{type(e).__name__}: {e}"
            print(f"FAIL {company:12s} ({ats}/{slug}): {error_message}")
            failures.append(company)
            code, outcome = classify_pull_error(error_message)
            failure_rows.append({
                "snapshot_date": snapshot_date,
                "watchlist_company": company,
                "ats": ats,
                "error_message": error_message[:2000],
                "error_code": code,
                "outcome": outcome,
            })

    def dedupe(rows, keys):
        seen = {}
        for r in rows:
            seen[tuple(r[k] for k in keys)] = r
        return list(seen.values())

    fact_rows = dedupe(fact_rows, ["snapshot_date", "watchlist_company", "ats_id"])
    dim_rows = dedupe(dim_rows, ["watchlist_company", "ats_id"])
    print(f"Prepared {len(fact_rows)} fact rows, {len(dim_rows)} dimension rows")

    if not fact_rows:
        print("ERROR: no rows pulled from any company; aborting before write.")
        sys.exit(1)

    resolve_workday_rollups(fact_rows, dim_rows)

    def upsert_chunked(table, rows, conflict, size=500):
        for i in range(0, len(rows), size):
            sb.table(table).upsert(rows[i:i + size], on_conflict=conflict).execute()
            print(f"  {table}: upserted {min(i + size, len(rows))}/{len(rows)}")

    def rpc_batched(fn_name, batch_size=2000):
        # Each call updates at most batch_size rows so a single statement never
        # runs long enough to hit the authenticator role's 8s statement_timeout.
        total = 0
        while True:
            resp = sb.rpc(fn_name, {"batch_size": batch_size}).execute()
            n = resp.data or 0
            total += n
            if n < batch_size:
                break
        return total

    print("Writing fact table...")
    upsert_chunked("raw_watchlist_jobs", fact_rows, "snapshot_date,watchlist_company,ats_id")
    print("Writing job dimension...")
    upsert_chunked("job_content", dim_rows, "watchlist_company,ats_id")

    print("Refreshing freshness columns...")
    sb.rpc("refresh_job_freshness", {"run_date": snapshot_date}).execute()
    print("  refresh_job_freshness done")

    print("Refreshing company first-seen dates...")
    sb.rpc("refresh_company_first_seen").execute()
    print("  refresh_company_first_seen done")

    print("Refreshing company last-seen dates...")
    sb.rpc("refresh_company_last_seen").execute()
    print("  refresh_company_last_seen done")

    print("Refreshing location flags...")
    sb.rpc("refresh_location_flags").execute()
    print("  refresh_location_flags done")

    print("Clearing descriptions for non-Seattle jobs...")
    n = rpc_batched("null_non_seattle_description")
    print(f"  cleared {n} descriptions")

    print("Clearing raw backup data for non-Seattle jobs...")
    n = rpc_batched("null_non_seattle_raw")
    print(f"  cleared {n} raw blobs")

    print("Pruning old raw snapshots...")
    RETENTION_DAYS = 7
    cutoff_date = (datetime.now(SEATTLE_TZ).date() - timedelta(days=RETENTION_DAYS)).isoformat()
    sb.table("raw_watchlist_jobs").delete().lt("snapshot_date", cutoff_date).execute()
    print(f"  raw_watchlist_jobs: pruned snapshots older than {cutoff_date}")

    fact_count = sb.table("raw_watchlist_jobs").select("ats_id", count="exact") \
        .eq("snapshot_date", snapshot_date).limit(1).execute().count
    dim_count = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    print(f"Verification: {fact_count} fact rows for {snapshot_date}, {dim_count} rows in job_content")

    print("Vacuuming raw_watchlist_jobs...")
    vacuum_full("raw_watchlist_jobs")
    print("Vacuuming job_content...")
    vacuum_full("job_content")

    # Capture stats right after vacuuming so table_stats reflects the
    # settled, post-reclaim size -- not mid-day dead-tuple bloat. This
    # used to be a separately scheduled workflow (capture-table-stats.yml,
    # 12:15 UTC) timed to run after the vacuum crons; that schedule already
    # drifted stale once when the vacuum crons moved to 13:45/13:49 UTC.
    # Running it right after this run's own vacuum can't drift.
    print("Capturing table stats...")
    for params in STATS_TARGETS:
        try:
            sb.rpc("capture_table_stats", params).execute()
        except Exception as e:
            print(f"WARNING: failed to capture stats for {params}: {type(e).__name__}: {e}")
    print("  capture_table_stats done")

    # job_stats is the business-facing counterpart to table_stats -- one row
    # per day of company/job counts by active-vs-new and Seattle/RemoteWA
    # geography (see capture_job_stats() in
    # supabase/migrations/20260730120100_create_capture_job_stats_function.sql).
    # Captured here for the same reason table_stats is: right after the
    # day's load and vacuum settle, so counts reflect the finished run.
    print("Capturing job stats...")
    try:
        sb.rpc("capture_job_stats").execute()
        print("  capture_job_stats done")
    except Exception as e:
        print(f"WARNING: failed to capture job stats: {type(e).__name__}: {e}")

    # Checkpoint successful companies so a same-day retry skips them (see
    # load_pull_successes). Best-effort: if this write fails, the only cost
    # is a retry re-scraping companies it didn't need to -- exactly today's
    # status quo -- not a lost or corrupted run.
    if success_rows:
        try:
            sb.table("pull_successes").upsert(
                success_rows, on_conflict="snapshot_date,watchlist_company"
            ).execute()
            print(f"Recorded {len(success_rows)} pull success(es) to pull_successes")
        except Exception as e:
            print(f"WARNING: failed to record pull successes to pull_successes: {type(e).__name__}: {e}")
        try:
            sb.table("pull_successes").delete().lt("snapshot_date", cutoff_date).execute()
        except Exception as e:
            print(f"WARNING: failed to prune old pull_successes rows: {type(e).__name__}: {e}")

    # pull_failures is an operational log table nothing else reads. Its own
    # write failing (e.g. a missing grant, as happened 2026-07-28) must not
    # exit(1) the run -- the real data load above already succeeded, and a
    # hard failure here previously caused a full re-scrape+re-upsert retry
    # of every company for no reason, tripling a day's write churn onto
    # job_content/raw_watchlist_jobs and bloating both past their vacuum
    # cadence. Log and move on instead.
    if failure_rows:
        try:
            sb.table("pull_failures").insert(failure_rows).execute()
            print(f"Logged {len(failure_rows)} pull failure(s) to pull_failures")
        except Exception as e:
            print(f"WARNING: failed to log pull failures to pull_failures: {type(e).__name__}: {e}")

    # Longer retention than raw snapshots (10d) -- this table exists to
    # surface week-over-week flakiness patterns per company, not just
    # today's run.
    try:
        FAILURE_RETENTION_DAYS = 30
        failure_cutoff = (datetime.now(SEATTLE_TZ).date() - timedelta(days=FAILURE_RETENTION_DAYS)).isoformat()
        sb.table("pull_failures").delete().lt("snapshot_date", failure_cutoff).execute()
    except Exception as e:
        print(f"WARNING: failed to prune old pull_failures rows: {type(e).__name__}: {e}")

    # Monitoring alert: one email to red.alert@heymeyer.com only if something
    # needs attention (BLOCKED today, dead-5-days, or repeat offenders).
    # Best-effort: wrapped so a send failure never breaks the run.
    try:
        send_alert_email(failure_rows, snapshot_date)
    except Exception as e:
        print(f"WARNING: send_alert_email raised: {type(e).__name__}: {e}")

    if failures:
        if len(failures) > MAX_TOLERATED_FAILURES:
            print(f"ERROR: pulls failed for: {failures}")
            sys.exit(1)
        print(f"WARNING: pulls failed for: {failures} (within tolerated threshold of {MAX_TOLERATED_FAILURES}, not failing the run)")


if __name__ == "__main__":
    main()
