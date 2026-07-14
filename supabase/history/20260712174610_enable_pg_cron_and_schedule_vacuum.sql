-- ARCHIVE ONLY. Not a replayable migration.
--
-- Recovered from supabase_migrations.schema_migrations on the jobs-tracker
-- project (gfwzdluwljtcbvmmkktd) before the migration history table was
-- repaired and a baseline snapshot was taken via `supabase db pull`.
--
-- These 16 statements were applied to the live database between 2026-07-10 and
-- 2026-07-13 (by Claude Code via the Supabase MCP apply_migration tool). They
-- assume base tables that were created by hand in the SQL editor and were never
-- captured in any migration, so this set CANNOT be replayed against an empty
-- database. Their effects are already folded into the baseline migration in
-- supabase/migrations/. Kept for the record, not for execution.
--
-- version: 20260712174610
-- name:    enable_pg_cron_and_schedule_vacuum

CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  'vacuum_full_watchlist_tables',
  '59 11 * * *',
  $$VACUUM FULL public.job_content; VACUUM FULL public.raw_watchlist_jobs;$$
);
