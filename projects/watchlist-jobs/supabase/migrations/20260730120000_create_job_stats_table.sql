-- JobStats: one row per day of business-facing counts (companies/jobs by
-- active-vs-new and Seattle/RemoteWA geography), as opposed to table_stats/
-- column_stats which track storage shape. Spec: BasicStats.xlsx (JobStats
-- tab). Populated by capture_job_stats() -- see
-- create_capture_job_stats_function.sql -- called from
-- fetch_watchlist_jobs.py right after the daily load, same place
-- capture_table_stats runs.
--
-- Company-count metrics below are scoped to companies that appear anywhere
-- in job_content (not filtered further by watchlist_companies.active), per
-- the spec's Table=Job_Content column. Since job_content is upsert-only and
-- never deletes rows, a company that stops being scraped still counts
-- toward the "zero active jobs" totals rather than dropping out of the
-- universe.
create table if not exists job_stats (
  snapshot_date date not null primary key,

  -- Table=Watchlist_Companies in the spec; the only metric sourced from
  -- watchlist_companies rather than job_content.
  company_count_watchlist_active_pull bigint,

  -- Companies with 0 vs 1+ active jobs (active = has a row in
  -- jobs_location_flags, which is already filtered to the latest snapshot).
  company_count_zero_active_jobs_global bigint,
  company_count_any_active_jobs_global bigint,
  company_count_any_active_jobs_seattle bigint,
  company_count_any_active_jobs_remote_wa bigint,
  company_count_any_active_jobs_seattle_or_remote_wa bigint,

  -- Companies with 0 vs 1+ new jobs (new = post_status in ('New','New*')).
  company_count_zero_new_jobs_global bigint,
  company_count_any_new_jobs_global bigint,
  company_count_any_new_jobs_seattle bigint,
  company_count_any_new_jobs_remote_wa bigint,
  company_count_any_new_jobs_seattle_or_remote_wa bigint,
  company_count_any_new_jobs_seattle_and_remote_wa bigint,

  -- Direct job counts (each row already unique per watchlist_company+ats_id).
  job_count_active_global bigint,
  job_count_active_seattle bigint,
  job_count_active_remote_wa bigint,
  job_count_active_seattle_or_remote_wa bigint,
  job_count_new_global bigint,
  job_count_new_seattle bigint,
  job_count_new_remote_wa bigint,
  job_count_new_seattle_or_remote_wa bigint,
  job_count_new_seattle_and_remote_wa bigint,

  captured_at timestamptz not null default now()
);

alter table job_stats enable row level security;

create policy "public read job_stats" on job_stats for select to anon using (true);
grant select on job_stats to anon;
grant select on job_stats to authenticated;
