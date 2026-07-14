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
-- version: 20260713152537
-- name:    point_jobs_location_flags_raw_at_job_content

CREATE OR REPLACE VIEW public.jobs_location_flags AS
 SELECT f.snapshot_date,
    f.watchlist_company,
    f.ats_id,
    f.ats_type,
    f.title,
    f.location,
    f.is_remote,
    f.department,
    f.team,
    f.employment_type,
    f.salary_min,
    f.salary_max,
    f.salary_currency,
    f.posted_at,
    f.fetched_at,
    f.url,
    f.apply_url,
    jc.raw,
    f.description_hash,
    jc.maybe_wa,
    jc.maybe_remote_wa,
    jc.discipline,
    jc.role_keyword,
    jc.level,
    wc.display_name,
    ((EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE ((r.category = 'discipline'::text) AND (r.value = jc.discipline)))) AND (EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE ((r.category = 'role'::text) AND (r.value = COALESCE(jc.role_keyword, '__unclassified__'::text))))) AND (EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE ((r.category = 'level'::text) AND (r.value = jc.level))))) AS is_target_match,
    jc.first_seen
   FROM ((raw_watchlist_jobs f
     LEFT JOIN job_content jc ON (((jc.watchlist_company = f.watchlist_company) AND (jc.ats_id = f.ats_id))))
     LEFT JOIN watchlist_companies wc ON ((wc.company = f.watchlist_company)));
