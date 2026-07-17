-- ats_company_directory has no snapshot/upsert-daily churn like job_content
-- or raw_watchlist_jobs; it's rebuilt in one monthly pass
-- (build_company_directory.py, cron on the 1st at 09:00 UTC, upsert + delete
-- of stale rows). That still leaves dead tuples, just on a monthly cadence
-- rather than daily. Schedule this 30 minutes after the monthly build
-- trigger fires -- the build itself completes in under a minute, so this is
-- a generous buffer, not a tight one.
--
-- One VACUUM FULL per cron.schedule call, matching the fix in
-- 20260714181838_restore_vacuum_full_cron.sql: pg_cron wraps multi-statement
-- commands in a transaction, and VACUUM FULL cannot run inside one.
select cron.schedule(
  'vacuum_full_ats_company_directory',
  '30 9 1 * *',
  $$VACUUM FULL public.ats_company_directory;$$
);
