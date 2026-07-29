-- The primary VACUUM FULL crons for job_content and raw_watchlist_jobs
-- (~13:45-13:51 UTC daily) have now failed to run cleanly on three separate
-- occasions from three unrelated causes: a pg_cron "job startup timeout",
-- a schedule-change migration landing after that day's slot had passed, and
-- (for the loader itself, not this cron, but same underlying fragility
-- theme) missing grants. Nothing caught any of these until someone noticed
-- the table had bloated.
--
-- This adds a same-day fallback: at 11pm Seattle time, only vacuum a table
-- if it hasn't already been vacuumed (by the primary cron or anything else)
-- since local midnight. cron.timezone is GMT with no per-job override, so
-- the trigger time is hardcoded as its current-DST UTC equivalent -- 06:00
-- UTC is 11pm PDT; when Seattle falls back to PST this becomes 10pm local
-- until the schedule is bumped to 07:00 UTC.
--
-- VACUUM cannot run inside a transaction block, so the guard is a PROCEDURE
-- (not a function) that COMMITs before each VACUUM statement -- procedures
-- are allowed transaction control, functions are not.
create or replace procedure public.vacuum_full_fallback(p_table regclass)
language plpgsql
as $$
declare
  v_last_vacuum timestamptz;
begin
  select last_vacuum into v_last_vacuum
  from pg_stat_user_tables
  where relid = p_table;

  if v_last_vacuum is not null
     and (v_last_vacuum at time zone 'America/Los_Angeles')::date
         = (now() at time zone 'America/Los_Angeles')::date then
    raise notice 'vacuum_full_fallback: % already vacuumed today, skipping', p_table;
    return;
  end if;

  commit;
  execute format('VACUUM FULL %s', p_table);
  commit;
  execute format('VACUUM %s', p_table);
end;
$$;

select cron.schedule(
  'vacuum_full_job_content_fallback',
  '0 6 * * *',
  $$CALL public.vacuum_full_fallback('public.job_content'::regclass)$$
);

select cron.schedule(
  'vacuum_full_raw_watchlist_jobs_fallback',
  '0 6 * * *',
  $$CALL public.vacuum_full_fallback('public.raw_watchlist_jobs'::regclass)$$
);
