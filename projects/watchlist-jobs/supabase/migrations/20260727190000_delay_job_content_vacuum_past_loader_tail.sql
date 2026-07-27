-- vacuum_full_job_content (11:59 UTC) / vacuum_job_content (12:01 UTC) assumed
-- the daily loader (watchlist-jobs.yml, nominally 09:00 UTC) always finished
-- well before noon. It doesn't: GitHub Actions schedule jitter plus
-- per-company retries (see raise_watchlist_jobs_failure_tolerance,
-- log_pull_failures) mean the loader sometimes doesn't finish until 12:30-13:15
-- UTC. When that happens, the loader's upsert churn lands AFTER that day's
-- VACUUM FULL, and the resulting heap/TOAST bloat sits untouched for a full
-- day (a later autovacuum clears n_dead_tup but does not shrink the file --
-- only VACUUM FULL does that) until the next 11:59 UTC run. That's what
-- inflated job_content to 215-227MB on 2026-07-24 and 2026-07-27 (real content
-- had grown by ~2MB; the rest was bloat). Reclaimed manually via VACUUM FULL
-- + VACUUM on 2026-07-27 (217MB -> 64MB) as an immediate fix; this migration
-- is the durable fix, moving both jobs to 13:45/13:47 UTC so they land after
-- even the late/retried loader runs observed so far, while still finishing
-- before capture_table_stats.py's nightly capture (observed running
-- 13:54-15:12 UTC per its own GitHub Actions jitter).
--
-- cron.schedule() with an existing job name updates that job's schedule in
-- place rather than creating a duplicate.
select cron.schedule(
  'vacuum_full_job_content',
  '45 13 * * *',
  $$VACUUM FULL public.job_content;$$
);

select cron.schedule(
  'vacuum_job_content',
  '47 13 * * *',
  $$VACUUM public.job_content;$$
);
