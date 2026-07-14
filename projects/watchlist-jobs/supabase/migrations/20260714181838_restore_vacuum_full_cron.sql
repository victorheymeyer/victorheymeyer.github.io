-- Restore the two daily VACUUM FULL jobs removed in 20260714175645.
--
-- These were incorrectly unscheduled earlier the same day on the mistaken
-- read that they were a leftover one-time reclaim. They are in fact the
-- working fix (from a separate session on 2026-07-13/14) for a real,
-- recurring bloat problem: the original combined job
-- (vacuum_full_watchlist_tables, migration 20260712174610) silently failed
-- every run because pg_cron wraps multi-statement commands in a transaction
-- and VACUUM FULL cannot run inside one. That let job_content's TOAST table
-- bloat to ~100 MB of dead space against ~26 MB of real content. Splitting
-- into two single-statement jobs fixed it; a manual VACUUM FULL reclaimed
-- the existing backlog (131 MB -> 28 MB), and the first scheduled runs on
-- 2026-07-14 completed successfully.

select cron.schedule(
  'vacuum_full_job_content',
  '59 11 * * *',
  $$VACUUM FULL public.job_content;$$
);

select cron.schedule(
  'vacuum_full_raw_watchlist_jobs',
  '0 12 * * *',
  $$VACUUM FULL public.raw_watchlist_jobs;$$
);
