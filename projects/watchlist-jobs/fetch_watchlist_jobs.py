# projects/watchlist-jobs/fetch_watchlist_jobs.py
import hashlib
import html as html_mod
import os
import re
import sys
from datetime import datetime, timezone

import httpx
from jobhive.scrapers import GreenhouseScraper, AshbyScraper
from supabase import create_client

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

SCRAPERS = {"greenhouse": GreenhouseScraper, "ashby": AshbyScraper}

# --- HTML description capture -------------------------------------------------
# jobhive flattens descriptions to plain text (Greenhouse: strips all tags;
# Ashby: picks descriptionPlain), destroying paragraph/bullet structure before
# we ever see it. To get renderable HTML we re-fetch the SAME public, no-auth
# endpoints jobhive uses and pull the HTML field directly, keyed by ats_id.
#
# Each extractor returns {str(ats_id): html_string}. To support a new ATS later,
# add one extractor and register it below. Any ATS without an extractor simply
# keeps jobhive's plain text (graceful fallback, nothing breaks).

def _greenhouse_html_map(slug, client):
    url = f"https://boards-api.greenhouse.io/v1/boards/{slug}/jobs?content=true"
    resp = client.get(url)
    resp.raise_for_status()
    out = {}
    for job in resp.json().get("jobs", []):
        content = job.get("content")
        if isinstance(content, str) and content.strip():
            # Greenhouse sends entity-escaped HTML; one unescape pass yields
            # real tags. Do NOT strip tags and do NOT unescape twice.
            out[str(job["id"])] = html_mod.unescape(content)
    return out


def _ashby_html_map(slug, client):
    url = f"https://api.ashbyhq.com/posting-api/job-board/{slug}?includeCompensation=true"
    resp = client.get(url)
    resp.raise_for_status()
    out = {}
    for job in resp.json().get("jobs", []):
        desc_html = job.get("descriptionHtml")
        if isinstance(desc_html, str) and desc_html.strip():
            out[str(job["id"])] = desc_html  # already clean HTML, no unescape
    return out


HTML_EXTRACTORS = {
    "greenhouse": _greenhouse_html_map,
    "ashby": _ashby_html_map,
}
# -----------------------------------------------------------------------------

# --- Discipline classification (frozen v4) -----------------------------------
# Maps a job title to one of 25 disciplines (craft/training, not org unit).
# Ordered rules, first match wins: specific/technical craft is matched before
# broad seniority words; Engineering (engineer/architect) precedes the
# blue-collar buckets; two late catch-alls ("analyst" -> Data & Analytics,
# "specialist" -> Customer Success) only fire when nothing domain-specific hit.
# Re-run every load so rule changes self-heal existing rows on the next pull.

_DISCIPLINE_RULES = [
    ("Executive", r"\b(chief|ceo|cfo|coo|cto|cmo|cro|cio|general manager|country manager|managing director|\bpresident\b|vice president|\bvp\b|\brvp\b|\bsvp\b|head of)\b", r"account executive"),
    ("Research", r"\b(research scientist|research engineer|researcher|applied scientist|research fellow|research intern|research lead|research manager|economist|ml researcher|ai researcher|machine learning researcher|postdoc|quantitative researcher|psychologist|fellows program|frontier agents intern)\b", None),
    ("Data & Analytics", r"\b(data analyst|business intelligence|bi analyst|analytics|data scientist|data science|business analyst|product analyst|digital analyst|insights|competitive intelligence|market intelligence|data quality)\b", None),
    ("Product Management", r"\b(product manager|product management|group product manager|director of product|product director|head of product|product owner|product lead)\b", None),
    ("Project/Program Management", r"\b(project manager|program manager|technical program|tpm|project lead|delivery manager|scrum master|scheduler|program director|special projects manager|project planner)\b", None),
    ("Design", r"\b(designer|design|\bux\b|\bui\b|user experience|creative director|creative lead|art director|motion graphics|graphic)\b", None),
    ("Engineering", r"\b(engineer|engineering|architect|developer|\bsre\b|devops|firmware|technical lead|software|\bswe\b|penetration tester|propulsion analyst|thermal analyst)\b", None),
    ("IT / Infrastructure", r"\b(data center|datacenter|it support|it network|it systems|systems administrator|network administrator|network infrastructure|help desk|helpdesk|it helpdesk|technology partner|desktop support|site reliability lead)\b", None),
    ("Security", r"\b(security analyst|security operator|security officer|soc analyst|threat|cyber|cybersecurity|information security|infosec|insider risk|physical security|security risk|incident response|security operations|comsec|security controls|security hardware|identity & access|iam\b)\b", None),
    ("Safety / EHS", r"\b(environmental health|health & safety|health and safety|\behs\b|industrial hygienist|safety specialist|specialist, safety|safety support|environmental specialist)\b", None),
    ("Quality / Inspection", r"\b(quality inspector|quality specialist|nde inspector|\bndt\b|\bnde\b|inspector|quality assurance|\bqa\b|precision inspector|welding inspector|quality control)\b", None),
    ("Skilled Trades", r"\b(welder|welding|machinist|\bcnc\b|\bedm\b|electrician|\bhvac\b|plumber|technician|mechanic|maintenance|fabricator|fabrication|tube bender|foreman|superintendent|journeyman|diamond turning|tool & die|tool and die|cmm programmer|driver)\b", r"data center technician|network|it support|it systems"),
    ("Manufacturing / Production", r"\b(production|manufacturing|assembly|build specialist|build supervisor|machine operator|operator|process operator|material handler|automation & controls|integration & test|integration specialist|test specialist|metrology|smt\b|receiving specialist|shipping specialist)\b", None),
    ("Supply Chain / Procurement", r"\b(sourcing|global supply|supply manager|supplier|buyer|procurement|inventory|materials management|purchasing|logistics|supply chain|warehouse|supply materials)\b", None),
    ("Hospitality / Facilities", r"\b(chef|cook|barista|porter|mixologist|food service|hospitality|facilities|janitor|custodian|soft services)\b", None),
    ("Sales", r"\b(sales|account executive|\bae\b|account manager|\bsdr\b|\bbdr\b|sales development|business development|revenue|go.?to.?market|\bgtm\b|partnerships|partner development|partner manager|partner lead|partner specialist|alliance|alliances|channel|account lead|account specialist|renewals|renewal manager|value advisor|relationship manager|market manager|growth lead|growth manager|growth specialist|enterprise\b|market access)\b", None),
    ("Marketing", r"\b(marketing|marketer|\bbrand\b|demand gen|demand generation|growth marketing|content|communications|\bcomms\b|social media|\bseo\b|\bsem\b|public relations|\bpr\b|copy|editor|events|campaign|paid media|analyst relations|web producer|photographer|technical writer)\b", None),
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

_DISCIPLINE_COMPILED = [
    (d, re.compile(p, re.I), re.compile(n, re.I) if n else None)
    for d, p, n in _DISCIPLINE_RULES
]


def classify_discipline(title):
    t = title or ""
    for discipline, pos, neg in _DISCIPLINE_COMPILED:
        if pos.search(t) and not (neg and neg.search(t)):
            return discipline
    return "Other"
# -----------------------------------------------------------------------------

snapshot_date = datetime.now(timezone.utc).date().isoformat()

FACT_COLS = ["snapshot_date", "watchlist_company", "ats_id", "ats_type", "title", "location",
             "is_remote", "department", "team", "employment_type", "salary_min", "salary_max",
             "salary_currency", "posted_at", "fetched_at", "url", "apply_url", "raw",
             "description_hash"]
DIM_COLS = ["watchlist_company", "ats_id", "title", "location", "department", "description",
            "url", "apply_url", "last_seen", "fetched_at", "discipline"]


def load_watchlist():
    """Read active companies from the watchlist_companies table."""
    resp = sb.table("watchlist_companies") \
        .select("company,ats,slug") \
        .eq("active", True) \
        .order("priority") \
        .execute()
    rows = resp.data or []
    watchlist = [
        {"company": r["company"], "ats": (r["ats"] or "").lower(), "slug": r["slug"]}
        for r in rows
    ]
    if not watchlist:
        print("ERROR: watchlist read returned 0 active companies; aborting "
              "(check the watchlist_companies table and DB connectivity).")
        sys.exit(1)
    return watchlist


def main():
    watchlist = load_watchlist()
    print(f"Loaded {len(watchlist)} active companies from watchlist_companies")

    fact_rows, dim_rows = [], []
    failures = []

    http = httpx.Client(timeout=30, follow_redirects=True)
    try:
        for entry in watchlist:
            company, ats, slug = entry["company"], entry["ats"], entry["slug"]
            if ats not in SCRAPERS:
                print(f"SKIP {company:12s}: unknown ats '{ats}' (no scraper)")
                failures.append(company)
                continue
            try:
                jobs = SCRAPERS[ats](slug).fetch()

                # Supplement with real HTML descriptions where we have an
                # extractor for this ATS. Failure here is non-fatal: we fall
                # back to jobhive's plain text for this company.
                html_map = {}
                extractor = HTML_EXTRACTORS.get(ats)
                if extractor:
                    try:
                        html_map = extractor(slug, http)
                    except Exception as e:
                        print(f"WARN {company:12s} HTML fetch failed "
                              f"({type(e).__name__}: {e}); using plain text")

                for j in jobs:
                    d = j.model_dump(mode="json")
                    d["snapshot_date"] = snapshot_date
                    d["watchlist_company"] = company
                    d["ats_id"] = str(d.get("ats_id"))
                    d["last_seen"] = snapshot_date

                    # Hash the PLAIN text (stable change-detection signal,
                    # noise-resistant to HTML re-serialization, zero churn).
                    plain = d.get("description")
                    d["description_hash"] = (
                        hashlib.sha256(plain.encode("utf-8")).hexdigest() if plain else None
                    )

                    # Store HTML for display; fall back to plain text if we
                    # didn't get HTML for this job.
                    d["description"] = html_map.get(d["ats_id"]) or plain

                    # Classify discipline from title (frozen v4 rules).
                    d["discipline"] = classify_discipline(d.get("title"))

                    fact_rows.append({k: d.get(k) for k in FACT_COLS})
                    dim_rows.append({k: d.get(k) for k in DIM_COLS})

                print(f"OK   {company:12s} ({ats}/{slug}): {len(jobs)} jobs, "
                      f"{len(html_map)} html")
            except Exception as e:
                print(f"FAIL {company:12s} ({ats}/{slug}): {type(e).__name__}: {e}")
                failures.append(company)
    finally:
        http.close()

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

    def upsert_chunked(table, rows, conflict, size=500):
        for i in range(0, len(rows), size):
            sb.table(table).upsert(rows[i:i + size], on_conflict=conflict).execute()
            print(f"  {table}: upserted {min(i + size, len(rows))}/{len(rows)}")

    print("Writing fact table...")
    upsert_chunked("raw_watchlist_jobs", fact_rows, "snapshot_date,watchlist_company,ats_id")
    print("Writing job dimension...")
    upsert_chunked("job_content", dim_rows, "watchlist_company,ats_id")

    print("Refreshing freshness columns...")
    sb.rpc("refresh_job_freshness", {"run_date": snapshot_date}).execute()
    print("  refresh_job_freshness done")

    fact_count = sb.table("raw_watchlist_jobs").select("ats_id", count="exact") \
        .eq("snapshot_date", snapshot_date).limit(1).execute().count
    dim_count = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    print(f"Verification: {fact_count} fact rows for {snapshot_date}, {dim_count} rows in job_content")

    if failures:
        print(f"ERROR: pulls failed for: {failures}")
        sys.exit(1)


if __name__ == "__main__":
    main()