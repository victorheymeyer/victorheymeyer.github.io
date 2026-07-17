# projects/watchlist-jobs/capture_table_stats.py
import os

from supabase import create_client

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# Each entry is the kwargs passed straight to the capture_table_stats RPC.
# p_stats_name lets a filtered slice of a table (e.g. job_content rows where
# seattle_and_remote = true, the only rows that keep description/raw) get
# captured under its own key in table_stats/column_stats, alongside the
# full-table capture. p_columns_only skips the whole-relation size fields for
# those slices, since a filtered subset's on-disk size isn't a meaningful
# number without a full re-scan.
TARGETS = [
    {"p_table": "job_content", "p_date_col": "last_seen"},
    {
        "p_table": "job_content",
        "p_date_col": "last_seen",
        "p_filter_column": "seattle_and_remote",
        "p_filter_value": True,
        "p_stats_name": "job_content_seattle_and_remote",
        "p_columns_only": True,
    },
    {"p_table": "raw_watchlist_jobs", "p_date_col": "snapshot_date"},
    {"p_table": "watchlist_companies"},
    {"p_table": "ats_company_directory", "p_date_col": "updated_at"},
]


def main():
    for params in TARGETS:
        sb.rpc("capture_table_stats", params).execute()
        stats_name = params.get("p_stats_name", params["p_table"])
        row = (
            sb.table("table_stats")
            .select("row_count,total_bytes")
            .eq("table_name", stats_name)
            .order("captured_date", desc=True)
            .limit(1)
            .execute()
            .data
        )
        print(f"{stats_name}: {row}")  # read-back verification, not the green check


if __name__ == "__main__":
    main()
