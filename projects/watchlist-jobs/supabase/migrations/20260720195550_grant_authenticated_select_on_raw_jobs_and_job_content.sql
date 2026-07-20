-- authenticated sessions could load jobs_location_flags but not the two
-- underlying tables my-jobs.html also queries directly: raw_watchlist_jobs
-- (latest snapshot_date lookup) and job_content (job description detail
-- panel). Both were only ever granted to anon, since before accounts
-- existed this page was never loaded by anything but a logged-out session.
grant select on public.raw_watchlist_jobs to authenticated;
grant select on public.job_content to authenticated;
