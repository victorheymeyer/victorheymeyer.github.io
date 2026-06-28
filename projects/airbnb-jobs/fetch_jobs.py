import os
import requests
from datetime import datetime, timezone
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
BOARD_URL = "https://boards-api.greenhouse.io/v1/boards/airbnb/jobs?content=true"


def main():
    sb = create_client(SUPABASE_URL, SERVICE_KEY)

    resp = requests.get(BOARD_URL, timeout=30)
    resp.raise_for_status()
    jobs = resp.json()["jobs"]

    snapshot_date = datetime.now(timezone.utc).date().isoformat()
    print(f"{len(jobs)} jobs, snapshot_date = {snapshot_date}")

    records = []
    for j in jobs:
        records.append({
            "snapshot_date": snapshot_date,
            "job_id": j["id"],
            "title": j.get("title"),
            "location_name": (j.get("location") or {}).get("name"),
            "company_name": j.get("company_name"),
            "requisition_id": j.get("requisition_id"),
            "absolute_url": j.get("absolute_url"),
            "updated_at": j.get("updated_at"),
            "first_published": j.get("first_published"),
            "application_deadline": j.get("application_deadline"),
            "language": j.get("language"),
            "departments": j.get("departments"),
            "offices": j.get("offices"),
            "metadata": j.get("metadata"),
            "content": j.get("content"),
            "raw": j,
        })

    def chunks(lst, n):
        for i in range(0, len(lst), n):
            yield lst[i:i + n]

    total = 0
    for batch in chunks(records, 100):
        result = sb.table("raw_airbnb_jobs").upsert(
            batch, on_conflict="snapshot_date,job_id"
        ).execute()
        total += len(result.data)
    print(f"Upserted {total} rows")

    check = (sb.table("raw_airbnb_jobs")
               .select("job_id", count="exact")
               .eq("snapshot_date", snapshot_date)
               .execute())
    print(f"Rows in Supabase for {snapshot_date}: {check.count}")

    if check.count != len(jobs):
        raise SystemExit(
            f"Row count mismatch: fetched {len(jobs)}, stored {check.count}"
        )


if __name__ == "__main__":
    main()