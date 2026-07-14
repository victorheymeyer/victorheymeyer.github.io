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
-- version: 20260713025142
-- name:    add_is_target_match_to_jobs_location_flags


create or replace view public.jobs_location_flags as
select
  f.snapshot_date,
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
  f.raw,
  f.description_hash,
  jc.maybe_wa,
  jc.maybe_remote_wa,
  jc.discipline,
  jc.role_keyword,
  jc.level,
  wc.display_name,
  (
    exists (select 1 from public.target_filter_rules r where r.category = 'discipline' and r.value = jc.discipline)
    and exists (select 1 from public.target_filter_rules r where r.category = 'role' and r.value = coalesce(jc.role_keyword, '__unclassified__'))
    and exists (select 1 from public.target_filter_rules r where r.category = 'level' and r.value = jc.level)
  ) as is_target_match
from public.raw_watchlist_jobs f
left join public.job_content jc on jc.watchlist_company = f.watchlist_company and jc.ats_id = f.ats_id
left join public.watchlist_companies wc on wc.company = f.watchlist_company;
