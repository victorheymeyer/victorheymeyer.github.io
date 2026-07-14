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
-- version: 20260713153650
-- name:    relocate_raw_to_job_content_drop_from_fact_table

DROP FUNCTION public.null_non_seattle_raw(date);

CREATE FUNCTION public.null_non_seattle_raw()
RETURNS void
LANGUAGE sql
AS $function$
  UPDATE job_content
  SET raw = NULL
  WHERE seattle_and_remote = false
    AND raw IS NOT NULL;
$function$;

ALTER TABLE public.raw_watchlist_jobs DROP COLUMN raw;
