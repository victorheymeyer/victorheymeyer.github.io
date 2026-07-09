# projects/watchlist-jobs/company-search/build_company_directory.py
#
# Downloads per-ATS company/slug CSVs (source: kalil0321/ats-scrapers on
# GitHub) and upserts them into a single ats_company_directory table in
# Supabase, keyed on (ats, slug). Run monthly via the
# company-directory-monthly.yml workflow, or manually:
#
#   pip install -r requirements.txt
#   JOBS_SUPABASE_URL=... JOBS_SUPABASE_SERVICE_KEY=... python build_company_directory.py
#
# Reuses the same JOBS_SUPABASE_URL / JOBS_SUPABASE_SERVICE_KEY secrets as
# fetch_watchlist_jobs.py -- same project, different table, no new secrets
# needed.

import csv
import io
import os
import sys
from datetime import datetime, timezone

import httpx
from supabase import create_client

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

BASE = "https://raw.githubusercontent.com/kalil0321/ats-scrapers/main/ats-companies"

# ats key -> csv filename (all files share the same name,slug,url schema)
ATS_FILES = {
    "ashby": "ashby.csv",
    "avature": "avature.csv",
    "bamboohr": "bamboohr.csv",
    "breezy": "breezy.csv",
    "cornerstone": "cornerstone.csv",
    "eightfold": "eightfold.csv",
    "gem": "gem.csv",
    "greenhouse": "greenhouse.csv",
    "icims": "icims.csv",
    "jazzhr": "jazzhr.csv",
    "join_com": "join_com.csv",
    "lever": "lever.csv",
    "personio": "personio.csv",
    "pinpoint": "pinpoint.csv",
    "recruiterbox": "recruiterbox.csv",
    "recruitee": "recruitee.csv",
    "rippling": "rippling.csv",
    "smartrecruiters": "smartrecruiters.csv",
    "successfactors": "successfactors.csv",
    "taleo": "taleo.csv",
    "teamtailor": "teamtailor.csv",
    "workable": "workable.csv",
    "workday": "workday.csv",
    "mercor": "mercor.csv",
    "oracle": "oracle.csv",
    # phenom.csv intentionally excluded: it uses a different schema
    # (url,name,company_code,locale,country) with no usable slug column
    # (company_code is blank for every current row), so there's nothing
    # to key a search on. Revisit if the source file adds real slugs.
}


def fetch_csv_rows(client, ats, filename):
    url = f"{BASE}/{filename}"
    resp = client.get(url)
    resp.raise_for_status()
    reader = csv.DictReader(io.StringIO(resp.text))
    rows = []
    for r in reader:
        company = (r.get("name") or "").strip()
        slug = (r.get("slug") or "").strip()
        if not company or not slug:
            continue
        rows.append({
            "company": company,
            "ats": ats,
            "slug": slug,
            "url": (r.get("url") or "").strip() or None,
        })
    return rows


def upsert_chunked(rows, size=500):
    for i in range(0, len(rows), size):
        sb.table("ats_company_directory").upsert(
            rows[i:i + size], on_conflict="ats,slug"
        ).execute()
        print(f"  upserted {min(i + size, len(rows))}/{len(rows)}")


def main():
    now = datetime.now(timezone.utc).isoformat()
    all_rows = []
    failures = []

    http = httpx.Client(timeout=30, follow_redirects=True)
    try:
        for ats, filename in ATS_FILES.items():
            try:
                rows = fetch_csv_rows(http, ats, filename)
                for r in rows:
                    r["updated_at"] = now
                all_rows.extend(rows)
                print(f"OK   {ats:16s}: {len(rows)} companies")
            except Exception as e:
                print(f"FAIL {ats:16s}: {type(e).__name__}: {e}")
                failures.append(ats)
    finally:
        http.close()

    # De-dupe within a single load (a company appearing twice in one CSV).
    seen = {}
    for r in all_rows:
        seen[(r["ats"], r["slug"])] = r
    all_rows = list(seen.values())

    print(f"Prepared {len(all_rows)} rows across {len(ATS_FILES) - len(failures)} ATS sources")

    if not all_rows:
        print("ERROR: no rows collected from any source; aborting before write.")
        sys.exit(1)

    print("Writing ats_company_directory...")
    upsert_chunked(all_rows)

    count = sb.table("ats_company_directory").select("id", count="exact").limit(1).execute().count
    print(f"Verification: {count} total rows in ats_company_directory")

    if failures:
        print(f"WARNING: sources failed to load: {failures}")
        # Non-fatal: a couple of failed sources shouldn't fail the whole
        # monthly refresh when most ATS's loaded fine.


if __name__ == "__main__":
    main()