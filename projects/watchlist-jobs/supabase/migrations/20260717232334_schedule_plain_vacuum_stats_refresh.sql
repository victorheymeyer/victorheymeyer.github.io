-- VACUUM FULL compacts the table but does not reliably refresh
-- pg_stat_user_tables.n_dead_tup in this environment; only a subsequent
-- plain VACUUM (or an autovacuum pass) does. job_content self-corrects by
-- coincidence because it autovacuums very frequently, but
-- raw_watchlist_jobs and ats_company_directory autovacuum much less often,
-- leaving a stale (non-zero) dead_tuples reading visible on the table stats
-- pages until autovacuum happens to fire. A cheap plain VACUUM shortly after
-- each VACUUM FULL guarantees the stat is correct before the nightly
-- capture reads it, regardless of autovacuum timing.
select cron.schedule(
  'vacuum_job_content',
  '1 12 * * *',
  $$VACUUM public.job_content;$$
);

select cron.schedule(
  'vacuum_raw_watchlist_jobs',
  '2 12 * * *',
  $$VACUUM public.raw_watchlist_jobs;$$
);

select cron.schedule(
  'vacuum_ats_company_directory',
  '32 9 1 * *',
  $$VACUUM public.ats_company_directory;$$
);
