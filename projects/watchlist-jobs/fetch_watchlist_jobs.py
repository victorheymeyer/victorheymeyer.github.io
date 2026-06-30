# projects/watchlist-jobs/fetch_watchlist_jobs.py
import hashlib
import html as html_mod
import os
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

snapshot_date = datetime.now(timezone.utc).date().isoformat()

FACT_COLS = ["snapshot_date", "watchlist_company", "ats_id", "ats_type", "title", "location",
             "is_remote", "department", "team", "employment_type", "salary_min", "salary_max",
             "salary_currency", "posted_at", "fetched_at", "url", "apply_url", "raw",
             "description_hash"]
DIM_COLS = ["watchlist_company", "ats_id", "title", "location", "department", "description",
            "url", "apply_url", "last_seen", "fetched_at"]


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