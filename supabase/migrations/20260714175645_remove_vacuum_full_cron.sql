-- Unschedule the daily VACUUM FULL jobs on job_content and raw_watchlist_jobs.
--
-- These were originally created as a single combined job
-- (vacuum_full_watchlist_tables, migration 20260712174610), which failed on
-- its first run and was later split into two separate jobs
-- (vacuum_full_job_content, vacuum_full_raw_watchlist_jobs) outside of any
-- migration. Table stats show low dead-tuple ratios with autovacuum already
-- keeping up on its own; VACUUM FULL's ACCESS EXCLUSIVE lock isn't earning
-- its nightly cost here. This appears to have been intended as a one-time
-- storage reclaim rather than a standing job.

select cron.unschedule('vacuum_full_job_content');
select cron.unschedule('vacuum_full_raw_watchlist_jobs');
