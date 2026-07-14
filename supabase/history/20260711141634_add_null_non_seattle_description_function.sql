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
-- version: 20260711141634
-- name:    add_null_non_seattle_description_function

CREATE OR REPLACE FUNCTION public.null_non_seattle_description()
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE job_content
  SET description = NULL
  WHERE seattle_and_remote = false
    AND description IS NOT NULL;
$function$;
