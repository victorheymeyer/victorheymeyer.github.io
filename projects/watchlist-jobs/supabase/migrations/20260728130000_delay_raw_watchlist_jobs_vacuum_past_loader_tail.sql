-- vacuum_full_raw_watchlist_jobs (12:00 UTC) / vacuum_raw_watchlist_jobs (12:02
-- UTC) have the same loader-timing exposure that delay_job_content_vacuum_past_loader_tail
-- (20260727190000) already fixed for job_content, but this pair was never moved:
-- the daily loader (watchlist-jobs.yml, nominally 09:00 UTC) sometimes doesn't
-- finish until 12:30-13:15 UTC (GitHub Actions jitter plus per-company retries --
-- see raise_watchlist_jobs_failure_tolerance, log_pull_failures), and it writes
-- to raw_watchlist_jobs on every chunked upsert. When a run is still going at
-- noon, VACUUM FULL's ACCESS EXCLUSIVE lock queues behind the loader's
-- in-flight writes and then makes every subsequent reader (including the
-- anon-role "latest snapshot_date" query every page fires first) queue behind
-- IT for the lock -- with anon's statement_timeout at only 3s, that's enough
-- to time out page loads. This is the likely source of intermittent
-- watchlist-jobs page timeouts distinct from the query-plan problem fixed by
-- the jobs_location_flags view rewrite.
--
-- Moving both jobs to 13:49/13:51 UTC: after job_content's 13:45/13:47 slot
-- (same reasoning: past the loader's observed late-finish tail) and before
-- capture_table_stats.py's nightly capture (observed running 13:54-15:12 UTC).
--
-- cron.schedule() with an existing job name updates that job's schedule in
-- place rather than creating a duplicate.
select cron.schedule(
  'vacuum_full_raw_watchlist_jobs',
  '49 13 * * *',
  $$VACUUM FULL public.raw_watchlist_jobs;$$
);

select cron.schedule(
  'vacuum_raw_watchlist_jobs',
  '51 13 * * *',
  $$VACUUM public.raw_watchlist_jobs;$$
);
