"""Company-discovery probe, steps 3a+3b+3c: fetch + classify one company
(probe_one, print-only), write its result to ats_probe_results
(write_probe_result), and run the full daily batch (main()) - call
next_probe_batch(), probe + write each company immediately, sleep between
companies, print a run summary. See the step 1-4 hand-off notes for the
full pipeline.

Two things are FAITHFUL to production:
  - SOFTWARE_KEYWORDS / TECH_EXTRA_KEYWORDS and seattle_rec(): copied
    verbatim from probe_preview.py (validated).
  - Location flags: ported from the live public.refresh_location_flags()
    SQL (pulled via pg_get_functiondef), NOT probe_preview.py's
    approximate regexes. See the "Location logic" section below.

Usage: python probe_ats.py   (requires JOBS_SUPABASE_URL / JOBS_SUPABASE_SERVICE_KEY)
"""

import json
import os
import re
import sys
import time
import urllib.request
from collections import Counter, defaultdict

# Location strings routinely carry non-ASCII characters (accented city
# names, etc.); Windows consoles default to cp1252, which can't encode all
# of them. Print output only, no effect on any write path.
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from ats_scrapers.exceptions import CompanyNotFoundError, ScraperError
from ats_scrapers.scrapers import get_scraper

# ============================================================================
# Keyword sets + seattle_rec: verbatim from probe_preview.py. Do not
# re-derive thresholds here.
# ============================================================================
SOFTWARE_KEYWORDS = [
    r"software", r"\bswe\b", r"developer",
    r"backend", r"back.?end", r"frontend", r"front.?end", r"full.?stack",
    r"data engineer",
]
TECH_EXTRA_KEYWORDS = [
    r"\bengineer", r"data scientist", r"machine learning", r"\bml\b", r"\bai\b",
    r"product manager", r"\bplatform\b", r"infrastructure", r"devops", r"\bsre\b",
    r"security engineer",
]
_SOFTWARE_RE = re.compile("|".join(SOFTWARE_KEYWORDS), re.I)
_TECH_RE = re.compile("|".join(SOFTWARE_KEYWORDS + TECH_EXTRA_KEYWORDS), re.I)


def is_software_title(title):
    return bool(_SOFTWARE_RE.search(title or ""))


def is_tech_title(title):
    return bool(_TECH_RE.search(title or ""))


PCT_STRONG = 0.10
PCT_MED = 0.05
PCT_LOW = 0.01
CNT_STRONG = 20
CNT_MED = 10
PCT_WATCH = 0.03
BIG_BOARD_HOLD = 1000
SMALL_BOARD = 100
CAPPED_TOTAL = 50
PAGINATED_ATS = {"workday", "smartrecruiters", "eightfold"}


def seattle_rec(ats, total, sw_count, sw_pct, local_present, outcome="ok"):
    if outcome == "error":
        return "Error", "fetch error - recorded, will not auto-retry"
    if outcome == "gone":
        return "Gone", "not on this ATS (migrated / slug changed)"
    if total == 0:
        return "Empty", "no listings (empty board) - done, no concern"

    strong = (sw_pct >= PCT_STRONG) or (sw_count >= CNT_STRONG)
    medium = (sw_pct >= PCT_MED) or (sw_count >= CNT_MED)
    low = (sw_pct >= PCT_LOW) or (sw_count >= 1)
    capped = ats in PAGINATED_ATS and total > CAPPED_TOTAL

    if not local_present:
        if sw_pct > PCT_WATCH:
            return "Maybe-later2", f"software {sw_pct:.0%} but no Seattle/RemoteWA - watch"
        return "Omit-NoLocal", "no Seattle/RemoteWA roles (low software)"

    if strong and total > BIG_BOARD_HOLD:
        return "Yes-Hold1", f"software ok ({sw_count} / {sw_pct:.0%}) but big board ({total}) - review"
    if strong and capped:
        return "Yes-Hold2", f"software ok ({sw_count} / {sw_pct:.0%}) on paginated ATS - review count"
    if strong and total <= BIG_BOARD_HOLD:
        return "Yes-Go", f"strong software: {sw_count} jobs / {sw_pct:.0%}"
    if total < SMALL_BOARD:
        return "Yes-SmallCoLowSW", f"small co ({total} jobs), local present, low software ({sw_count} / {sw_pct:.0%}) - quick review"
    if medium:
        return "Maybe-Good", f"medium software: {sw_count} / {sw_pct:.0%}"
    if low:
        return "Maybe-Low", f"low software: {sw_count} / {sw_pct:.0%}"
    return "Omit-NoSWjobs", f"big board ({total}), ~no software ({sw_pct:.0%})"


_HTTP_RE = re.compile(r"\b([45]\d\d)\b")


def extract_http_status(msg):
    m = _HTTP_RE.search(msg or "")
    return int(m.group(1)) if m else None


# ============================================================================
# Location logic - ported from public.refresh_location_flags() (pulled via
# `select pg_get_functiondef(oid) from pg_proc where proname =
# 'refresh_location_flags'`), NOT probe_preview.py's approximation. That SQL
# only implements WA/Remote-WA; bay/nyc/remote_ca/remote_ny extend the same
# structure to new states per the step 1 hand-off's disambiguation rules.
#
# Deliberate deviation from probe_preview.py: refresh_location_flags derives
# everything from the `location` string alone -- it never consults a
# separate is_remote flag. This port does the same (ignores Job.is_remote),
# unlike probe_preview.py's loc_flags() which OR'd is_remote in directly. A
# listing whose location text doesn't say "remote" anywhere won't count
# toward any remote bucket here even if the scraper's own is_remote
# heuristic says True.
# ============================================================================

# Postgres `location ~ '^[A-Z]{2}-'` is case-sensitive; `!~* '^US-'` is not.
_LOCALE_PREFIX_RE = re.compile(r"^[A-Z]{2}-")
_US_PREFIX_RE = re.compile(r"^US-", re.I)


def _locale_prefix_blocked(s):
    return bool(_LOCALE_PREFIX_RE.match(s)) and not bool(_US_PREFIX_RE.match(s))


_DC_PATTERN = r"\bdc\b|d\.c\.?|district of columbia"
_DC_RE = re.compile(_DC_PATTERN, re.I)

# All 50 states, abbreviation + full name, transcribed from
# refresh_location_flags()'s maybe_wa exclusion list (which enumerates every
# state but WA) plus WA itself appended. Building each flag's "other states"
# exclusion from one table, rather than hand-copying near-duplicate 49-item
# alternations per flag, to avoid a transcription slip in any one of them.
_ALL_STATES = [
    ("al", "alabama"), ("ak", "alaska"), ("az", "arizona"), ("ar", "arkansas"),
    ("ca", "california"), ("co", "colorado"), ("ct", "connecticut"), ("de", "delaware"),
    ("fl", "florida"), ("ga", "georgia"), ("hi", "hawaii"), ("id", "idaho"),
    ("il", "illinois"), ("in", "indiana"), ("ia", "iowa"), ("ks", "kansas"),
    ("ky", "kentucky"), ("la", "louisiana"), ("me", "maine"), ("md", "maryland"),
    ("ma", "massachusetts"), ("mi", "michigan"), ("mn", "minnesota"), ("ms", "mississippi"),
    ("mo", "missouri"), ("mt", "montana"), ("ne", "nebraska"), ("nv", "nevada"),
    ("nh", "new hampshire"), ("nj", "new jersey"), ("nm", "new mexico"), ("ny", "new york"),
    ("nc", "north carolina"), ("nd", "north dakota"), ("oh", "ohio"), ("ok", "oklahoma"),
    ("or", "oregon"), ("pa", "pennsylvania"), ("ri", "rhode island"), ("sc", "south carolina"),
    ("sd", "south dakota"), ("tn", "tennessee"), ("tx", "texas"), ("ut", "utah"),
    ("vt", "vermont"), ("va", "virginia"), ("wv", "west virginia"), ("wi", "wisconsin"),
    ("wy", "wyoming"), ("wa", "washington"),
]


def _other_states_re(own_abbr):
    words = [w for abbr, name in _ALL_STATES if abbr != own_abbr for w in (abbr, name)]
    alt = "|".join(re.escape(w) for w in words)
    return re.compile(rf"\b({alt})\b|{_DC_PATTERN}", re.I)


_WA_WORD_RE = re.compile(r"\b(wa|washington)\b", re.I)
_WA_CITY_RE = re.compile(
    r"\b(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|"
    r"issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|"
    r"tacoma|spokane)\b",
    re.I,
)
_WA_OTHER_STATES_RE = _other_states_re("wa")

_NY_WORD_RE = re.compile(r"\b(ny|new york)\b", re.I)
# City list not covered by refresh_location_flags (DB only implements
# WA/Remote-WA) -- built from probe_preview.py's first-draft NYC_CITY list,
# per the step-1 hand-off note that Bay/NYC were flagged as first-draft.
# Flagging for review since there's no DB ground truth for it.
_NYC_CITY_RE = re.compile(
    r"\b(new york city|nyc|manhattan|brooklyn|queens|the bronx|bronx|"
    r"long island city|jersey city|newark|hoboken)\b",
    re.I,
)
_NY_OTHER_STATES_RE = _other_states_re("ny")

# Same "no DB ground truth" note as NYC_CITY above.
_BAY_CITY_RE = re.compile(
    r"\b(san francisco|south san francisco|san jose|palo alto|mountain view|"
    r"sunnyvale|oakland|menlo park|redwood city|santa clara|cupertino|"
    r"berkeley|emeryville|bay area)\b",
    re.I,
)
# California/Canada disambiguation (step-1 hand-off, positive approach):
# full word "California" always counts; bare "CA" only in unambiguous
# US-postal context (", CA" at string end, or ", CA <ZIP>").
_CA_FULLWORD_RE = re.compile(r"\bcalifornia\b", re.I)
_CA_POSTAL_RE = re.compile(r",\s*ca(?:\s+\d{5}(?:-\d{4})?)?\s*$", re.I)
_CA_OTHER_STATES_RE = _other_states_re("ca")


def _is_wa_onsite(s):
    word_branch = (
        bool(_WA_WORD_RE.search(s))
        and not _locale_prefix_blocked(s)
        and not bool(_WA_OTHER_STATES_RE.search(s))
    )
    return word_branch or bool(_WA_CITY_RE.search(s))


def _is_ny_onsite(s):
    word_branch = (
        bool(_NY_WORD_RE.search(s))
        and not _locale_prefix_blocked(s)
        and not bool(_NY_OTHER_STATES_RE.search(s))
    )
    return word_branch or bool(_NYC_CITY_RE.search(s))


def _is_bay_onsite(s):
    ca_word_branch = (
        (bool(_CA_FULLWORD_RE.search(s)) or bool(_CA_POSTAL_RE.search(s)))
        and not _locale_prefix_blocked(s)
        and not bool(_CA_OTHER_STATES_RE.search(s))
    )
    return ca_word_branch or bool(_BAY_CITY_RE.search(s))


# --- Remote variants: DC-only exclusion (not the 49-state list), remote-US
# generic branches folded in, mirroring maybe_remote_wa exactly. ---

_REMOTE_WORD_RE = re.compile(r"\b(remote|anywhere)\b", re.I)
_USA_RE = re.compile(r"\b(usa|united states|north america)\b", re.I)
_NATIONWIDE_RE = re.compile(r"\b(nationwide|national|global|worldwide|flexible)\b", re.I)
_BARE_REMOTE_RE = re.compile(r"^\s*(remote|anywhere)(\s*[;|,]\s*(remote|anywhere))*\s*$", re.I)
_SEGMENT_SPLIT_RE = re.compile(r"\s*[;|,]\s*")
_PAREN_STRIP_RE = re.compile(r"[()]")
_REMOTE_US_SEGMENT_PATTERNS = [
    re.compile(r"^\s*(the\s+)?u\.?s\.?a?\.?\s*[-,]?\s*(based\s*)?remote\s*$", re.I),
    re.compile(r"^\s*remote\s*[-,]?\s*(based\s*)?(the\s+)?u\.?s\.?a?\.?\s*$", re.I),
    re.compile(r"^\s*(the\s+)?u\.?s\.?a?\.?\s*$", re.I),
    re.compile(r"^\s*remote\s+in\s+the\s+u\.?s\.?a?\.?\s*$", re.I),
]


def _has_remote_us_segment(s):
    for seg in _SEGMENT_SPLIT_RE.split(s):
        cleaned = _PAREN_STRIP_RE.sub("", seg)
        if any(p.match(cleaned) for p in _REMOTE_US_SEGMENT_PATTERNS):
            return True
    return False


def _is_remote_generic(s):
    return (
        bool(_USA_RE.search(s))
        or bool(_NATIONWIDE_RE.search(s))
        or _has_remote_us_segment(s)
        or bool(_BARE_REMOTE_RE.match(s))
    )


def _is_remote_wa(s):
    if not _REMOTE_WORD_RE.search(s):
        return False
    # DC exclusion here is load-bearing: the word "washington" is genuinely
    # ambiguous with "Washington, D.C.", so a remote listing that says
    # "Washington, D.C." must not count as remote_wa. Matches
    # maybe_remote_wa's WA-word branch exactly.
    wa_branch = (
        bool(_WA_WORD_RE.search(s))
        and not _locale_prefix_blocked(s)
        and not bool(_DC_RE.search(s))
    )
    return wa_branch or bool(_WA_CITY_RE.search(s)) or _is_remote_generic(s)


def _is_remote_ny(s):
    if not _REMOTE_WORD_RE.search(s):
        return False
    # No DC exclusion here (unlike remote_wa): "new york"/"ny" has no word
    # collision with DC the way "washington" does, so there's nothing to
    # guard against.
    ny_branch = bool(_NY_WORD_RE.search(s)) and not _locale_prefix_blocked(s)
    return ny_branch or bool(_NYC_CITY_RE.search(s)) or _is_remote_generic(s)


def _is_remote_ca(s):
    if not _REMOTE_WORD_RE.search(s):
        return False
    # Remote-CA: full "California" or a CA city only - no bare "CA" at all
    # (even in postal context), to avoid Canada's CA country code. Stricter
    # than onsite bay, which allows bare CA in clear US-postal context. No
    # DC exclusion (unlike remote_wa): "california"/"ca" has no word
    # collision with DC, so there's nothing to guard against.
    ca_branch = bool(_CA_FULLWORD_RE.search(s)) and not _locale_prefix_blocked(s)
    return ca_branch or bool(_BAY_CITY_RE.search(s)) or _is_remote_generic(s)


def loc_flags(location):
    s = (location or "").strip()
    if not s:
        return {k: False for k in ("wa", "bay", "nyc", "remote_wa", "remote_ca", "remote_ny")}
    return {
        "wa": _is_wa_onsite(s),
        "bay": _is_bay_onsite(s),
        "nyc": _is_ny_onsite(s),
        "remote_wa": _is_remote_wa(s),
        "remote_ca": _is_remote_ca(s),
        "remote_ny": _is_remote_ny(s),
    }


# ============================================================================
# probe_one - fetch + classify. Prints only; writes nothing.
# ============================================================================

def probe_one(ats, identifier):
    t0 = time.time()
    try:
        scraper = get_scraper(ats, identifier, include_descriptions=False)
        jobs = scraper.fetch()
    except Exception as e:
        outcome = "gone" if isinstance(e, CompanyNotFoundError) else "error"
        msg = str(e)
        http_status = extract_http_status(msg)
        rec, note = seattle_rec(ats, 0, 0, 0.0, local_present=False, outcome=outcome)
        return {
            "ats": ats, "identifier": identifier, "status": outcome,
            "total_jobs": None, "http_status": http_status, "error_detail": msg[:200],
            "seattle_rec": rec, "seattle_rec_note": note,
            "secs": round(time.time() - t0, 1),
        }

    tech_jobs = 0
    sw_jobs = 0
    loc_counts = Counter({k: 0 for k in ("wa", "bay", "nyc", "remote_wa", "remote_ca", "remote_ny")})
    unmatched = Counter()

    for j in jobs:
        title = getattr(j, "title", None) or ""
        location = getattr(j, "location", None)
        if is_tech_title(title):
            tech_jobs += 1
        if is_software_title(title):
            sw_jobs += 1
        flags = loc_flags(location)
        for k, v in flags.items():
            if v:
                loc_counts[k] += 1
        if not any(flags.values()):
            unmatched[location or "(blank)"] += 1

    total_jobs = len(jobs)
    status = "empty" if total_jobs == 0 else "ok"
    tech_pct = (tech_jobs / total_jobs) if total_jobs else 0.0
    software_pct = (sw_jobs / total_jobs) if total_jobs else 0.0
    local = loc_counts["wa"] + loc_counts["remote_wa"]
    rec, note = seattle_rec(ats, total_jobs, sw_jobs, software_pct, local_present=(local > 0))

    return {
        "ats": ats, "identifier": identifier, "status": status,
        "total_jobs": total_jobs, "http_status": 200, "error_detail": None,
        "tech_jobs": tech_jobs, "tech_pct": round(tech_pct, 3),
        "sw_jobs": sw_jobs, "software_pct": round(software_pct, 3),
        "wa_jobs": loc_counts["wa"], "bay_jobs": loc_counts["bay"], "nyc_jobs": loc_counts["nyc"],
        "remote_wa_jobs": loc_counts["remote_wa"], "remote_ca_jobs": loc_counts["remote_ca"],
        "remote_ny_jobs": loc_counts["remote_ny"],
        "local": local,
        "unmatched_locations": dict(unmatched.most_common(10)),
        "seattle_rec": rec, "seattle_rec_note": note,
        "secs": round(time.time() - t0, 1),
    }


# ============================================================================
# write_probe_result - step 3b. Writes exactly one row per call; the loop
# (step 3c) calls this once per company immediately after probing it, never
# batched, so a mid-run crash resumes cleanly via next_probe_batch()'s
# exclusion query.
# ============================================================================

_sb_client = None


def _get_client():
    """Lazy import + init so importing this module for probe_one() alone
    (3a's print-only use) never requires the supabase package or
    credentials - only calling write_probe_result() does."""
    global _sb_client
    if _sb_client is None:
        import os
        from supabase import create_client
        url = os.environ["JOBS_SUPABASE_URL"]
        key = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
        _sb_client = create_client(url, key)
    return _sb_client


def write_probe_result(row, *, slug, url, company):
    """Insert one probe_one() row into ats_probe_results.

    row: the dict probe_one() returned.
    slug: the directory slug (NOT the scraper identifier) - this is what
        next_probe_batch()'s exclusion query and the view's join key match
        on, so it must be the directory's slug even when identifier was a
        full Workday URL.
    url: the identifier that was actually passed to get_scraper() (the
        Workday URL, or the bare slug for every other ATS) - stored
        separately to satisfy the table's own `url` NOT NULL column.
    company: directory company name. probe_one() doesn't carry any of
        these three - it only knows ats/identifier - so the caller (3c's
        loop, or this module's own verification block) supplies them from
        whatever produced the (ats, slug, identifier, company) tuple in
        the first place (next_probe_batch() in 3c).

    Always INSERTs, never upserts - the table is append-mode, and
    ats_probe_latest already takes the latest row per (ats, slug) via
    DISTINCT ON. probed_at is left to the column's own `default now()`
    rather than set here, to avoid any client/DB clock skew.
    """
    payload = {
        "ats": row["ats"],
        "slug": slug,
        "url": url,
        "company": company,
        "status": row["status"],
        "http_status": row.get("http_status"),
        "error_detail": row.get("error_detail"),
        "total_jobs": row.get("total_jobs"),
        "tech_jobs": row.get("tech_jobs"),
        "sw_jobs": row.get("sw_jobs"),
        "wa_jobs": row.get("wa_jobs"),
        "bay_jobs": row.get("bay_jobs"),
        "nyc_jobs": row.get("nyc_jobs"),
        "remote_wa_jobs": row.get("remote_wa_jobs"),
        "remote_ca_jobs": row.get("remote_ca_jobs"),
        "remote_ny_jobs": row.get("remote_ny_jobs"),
        "unmatched_locations": row.get("unmatched_locations"),
    }
    _get_client().table("ats_probe_results").insert(payload).execute()
    return payload


def _print_row(r):
    if r["status"] in ("gone", "error"):
        print(f"[{r['ats']:15}] {r['identifier'][:50]:50} {r['status']:6} "
              f"(HTTP {r['http_status']}): {r['error_detail']} | {r['secs']}s")
        return
    print(f"[{r['ats']:15}] {r['identifier'][:50]:50} {r['status']:6} "
          f"{r['total_jobs']:>5} jobs | tech {r['tech_pct']:>5.0%} sw {r['software_pct']:>5.0%} | "
          f"WA {r['wa_jobs']:>3} rWA {r['remote_wa_jobs']:>3} BAY {r['bay_jobs']:>3} "
          f"NYC {r['nyc_jobs']:>3} rCA {r['remote_ca_jobs']:>3} rNY {r['remote_ny_jobs']:>3} | "
          f"{r['seattle_rec']:16} ({r['seattle_rec_note']}) | {r['secs']}s")
    if r["unmatched_locations"]:
        print(f"    unmatched: {r['unmatched_locations']}")


def _run_3a_demo():
    """The 3a verification set (kept for manual re-checking of probe_one()
    alone; not the script's default entrypoint - see main())."""
    VERIFICATION_SET = [
        # Known software, Seattle-present -> expect Yes-Go.
        ("greenhouse", "amperity"),
        ("greenhouse", "extrahopnetworks"),
        # Non-software, huge board -> expect a Maybe/Omit/Hold tier, not Yes-Go.
        ("workday", "https://cat.wd5.myworkdayjobs.com/CaterpillarCareers"),
        # Terminal cases.
        ("greenhouse", "this-company-definitely-does-not-exist-12345"),  # -> gone
        ("eightfold", "citi"),      # -> error (rate-limited)
        ("eightfold", "deloitte"),  # -> error (404)
        # CA/Canada disambiguation: Vancouver-headquartered, listings include
        # "Vancouver, British Columbia, Canada" / "Toronto, Ontario, Canada" -
        # none of those should inflate bay_jobs/remote_ca_jobs.
        ("greenhouse", "hootsuite"),
    ]
    for ats, identifier in VERIFICATION_SET:
        _print_row(probe_one(ats, identifier))


# ============================================================================
# main() - step 3c-1: the daily loop. Calls next_probe_batch(), probes and
# writes each company immediately (never batched), sleeps between
# companies, prints a run summary. Write failures are caught per-company
# and logged (see the try/except in the loop below) rather than aborting
# the run.
# ============================================================================

# Gentle-on-providers delay between companies. Paginated ATS (multi-request
# fetches, already observed rate-limiting Citi in 3a) get a longer gap.
DEFAULT_SLEEP_SECONDS = 1.0
PAGINATED_SLEEP_SECONDS = 2.0

# Testing-only: set PROBE_CAP_OVERRIDE=2 to trim each ATS's slice of the
# batch to N companies (queue order preserved) instead of the function's
# real 100/20 caps. Unset in production - next_probe_batch()'s own caps
# apply untouched.
_CAP_OVERRIDE_ENV = "PROBE_CAP_OVERRIDE"

# Same Resend setup as fetch_watchlist_jobs.py's send_alert_email().
ALERT_TO = "red.alert@heymeyer.com"
ALERT_FROM = "Probe Pipeline <alerts@mail.heymeyer.com>"


def _auto_approve_and_alert():
    """Call auto_approve_probe_decisions() (Yes-Go / Yes-SmallCoLowSW tiers
    only - see the 20260824190000 migration) and, if it approved anything,
    email a summary. Never raises - a failure here shouldn't fail the run
    that already wrote this batch's probe results."""
    try:
        resp = _get_client().rpc("auto_approve_probe_decisions", {}).execute()
        approved = resp.data or []
    except Exception as e:
        print(f"WARNING: auto_approve_probe_decisions RPC failed: {type(e).__name__}: {e}")
        return

    if not approved:
        print("Auto-approve: nothing new to approve.")
        return

    by_tier = defaultdict(list)
    for row in approved:
        by_tier[row["out_seattle_rec"]].append(f"{row['out_company']} ({row['out_ats']}/{row['out_slug']})")
    print(f"Auto-approved {len(approved)} companies: " +
          ", ".join(f"{tier}={len(rows)}" for tier, rows in sorted(by_tier.items())))

    api_key = os.environ.get("RESEND_API_KEY")
    if not api_key:
        print("WARNING: RESEND_API_KEY not set; skipping auto-approve alert email.")
        return

    lines = [f"Auto-approved {len(approved)} companies from today's probe run:", ""]
    for tier, rows in sorted(by_tier.items()):
        lines.append(f"[{tier}] ({len(rows)}):")
        for r in sorted(rows):
            lines.append(f"    - {r}")
        lines.append("")
    body = "\n".join(lines)

    payload = json.dumps({
        "from": ALERT_FROM,
        "to": [ALERT_TO],
        "subject": f"Probe auto-approve: {len(approved)} companies added",
        "text": body,
    }).encode("utf-8")

    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "probe-alerts/1.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            print(f"Auto-approve alert email sent to {ALERT_TO} (HTTP {resp.status})")
    except Exception as e:
        print(f"WARNING: auto-approve alert email failed to send: {type(e).__name__}: {e}")


def _fetch_batch(cap_override=None):
    resp = _get_client().rpc("next_probe_batch", {}).execute()
    batch = resp.data or []
    if cap_override is None:
        return batch
    trimmed = []
    seen_per_ats = defaultdict(int)
    for entry in batch:
        ats = entry["ats"].lower()
        if seen_per_ats[ats] < cap_override:
            trimmed.append(entry)
            seen_per_ats[ats] += 1
    return trimmed


def main():
    cap_env = os.environ.get(_CAP_OVERRIDE_ENV)
    cap_override = int(cap_env) if cap_env else None
    if cap_override is not None:
        print(f"** {_CAP_OVERRIDE_ENV}={cap_override} - testing cap, NOT production caps **")

    batch = _fetch_batch(cap_override=cap_override)
    print(f"Batch: {len(batch)} companies")

    t_start = time.time()
    outcome_counts = defaultdict(lambda: defaultdict(int))
    error_rows = []
    write_failures = []

    for entry in batch:
        ats = entry["ats"]
        slug = entry["slug"]
        identifier = entry["identifier"]
        directory_url = entry["directory_url"]
        company = entry["company"]

        row = probe_one(ats, identifier)
        _print_row(row)
        outcome_counts[ats][row["status"]] += 1
        if row["status"] == "error":
            error_rows.append((ats, slug, row.get("http_status"), row.get("error_detail")))

        # Write failure (transient Supabase/network error) -> skip this
        # company, log it, keep going. Do not abort the run: the exclusion
        # query is self-healing (no row -> reappears in the next batch), so
        # aborting would only waste the companies already written this run.
        try:
            write_probe_result(row, slug=slug, url=directory_url, company=company)
        except Exception as e:
            write_failures.append((ats, slug, str(e)))
            print(f"    WRITE FAILED for {ats}/{slug}: {e}")

        time.sleep(PAGINATED_SLEEP_SECONDS if ats.lower() in PAGINATED_ATS else DEFAULT_SLEEP_SECONDS)

    elapsed = time.time() - t_start
    _print_run_summary(batch, outcome_counts, elapsed, error_rows, write_failures)

    try:
        _auto_approve_and_alert()
    except Exception as e:
        print(f"WARNING: _auto_approve_and_alert raised: {type(e).__name__}: {e}")


def _print_run_summary(batch, outcome_counts, elapsed, error_rows, write_failures):
    print("\n===== RUN SUMMARY =====")
    for ats in sorted(outcome_counts):
        counts = outcome_counts[ats]
        parts = ", ".join(f"{status}={n}" for status, n in sorted(counts.items()))
        print(f"  {ats:16} {parts}")
    print(f"  total companies probed: {len(batch)}")
    print(f"  total wall time: {elapsed:.1f}s")
    if error_rows:
        print("  errors:")
        for ats, slug, http_status, detail in error_rows:
            print(f"    [{ats}] {slug} (HTTP {http_status}): {detail}")
    if write_failures:
        print("  WRITE FAILURES:")
        for ats, slug, msg in write_failures:
            print(f"    [{ats}] {slug}: {msg}")


if __name__ == "__main__":
    main()
