# projects/watchlist-jobs/fetch_watchlist_jobs.py
import hashlib
import os
import sys
from datetime import datetime, timezone

from jobhive.scrapers import GreenhouseScraper, AshbyScraper
from supabase import create_client

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

WATCHLIST = [
    {"company": "databricks", "ats": "greenhouse", "slug": "databricks"},
    {"company": "rubrik",     "ats": "greenhouse", "slug": "rubrik"},
    {"company": "snowflake",  "ats": "ashby",      "slug": "snowflake"},
]
SCRAPERS = {"greenhouse": GreenhouseScraper, "ashby": AshbyScraper}

snapshot_date = datetime.now(timezone.utc).date().isoformat()

FACT_COLS = ["snapshot_date", "watchlist_company", "ats_id", "ats_type", "title", "location",
             "is_remote", "department", "team", "employment_type", "salary_min", "salary_max",
             "salary_currency", "posted_at", "fetched_at", "url", "apply_url", "raw",
             "description_hash"]
DIM_COLS = ["watchlist_company", "ats_id", "title", "location", "department", "description",
            "url", "apply_url", "last_seen", "fetched_at"]


def main():
    fact_rows, dim_rows = [], []
    failures = []

    for entry in WATCHLIST:
        company, ats, slug = entry["company"], entry["ats"], entry["slug"]
        try:
            jobs = SCRAPERS[ats](slug).fetch()
            for j in jobs:
                d = j.model_dump(mode="json")
                d["snapshot_date"] = snapshot_date
                d["watchlist_company"] = company
                d["ats_id"] = str(d.get("ats_id"))
                d["last_seen"] = snapshot_date
                desc = d.get("description")
                d["description_hash"] = hashlib.sha256(desc.encode("utf-8")).hexdigest() if desc else None
                fact_rows.append({k: d.get(k) for k in FACT_COLS})
                dim_rows.append({k: d.get(k) for k in DIM_COLS})
            print(f"OK   {company:12s} ({ats}/{slug}): {len(jobs)} jobs")
        except Exception as e:
            print(f"FAIL {company:12s} ({ats}/{slug}): {type(e).__name__}: {e}")
            failures.append(company)

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

    fact_count = sb.table("raw_watchlist_jobs").select("ats_id", count="exact") \
        .eq("snapshot_date", snapshot_date).limit(1).execute().count
    dim_count = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    print(f"Verification: {fact_count} fact rows for {snapshot_date}, {dim_count} rows in job_content")

    if failures:
        print(f"ERROR: pulls failed for: {failures}")
        sys.exit(1)


if __name__ == "__main__":
    main()