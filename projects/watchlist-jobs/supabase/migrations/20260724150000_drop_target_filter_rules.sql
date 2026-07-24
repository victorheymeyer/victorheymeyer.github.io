-- target_filter_rules was the old, single global "target" definition
-- (discipline/role/level combos) used to compute jobs_location_flags.is_target_match.
-- It has been superseded by user_criteria.filters, which lets each account save
-- its own criteria instead of everyone sharing one hardcoded set. Nothing reads
-- is_target_match: no application code selects it, and no function or view other
-- than jobs_location_flags itself references target_filter_rules (confirmed via
-- pg_depend and a pg_proc source scan before writing this migration).
--
-- CREATE OR REPLACE VIEW cannot drop a column from the middle of a view's
-- column list, so the view is dropped and recreated instead of patched in
-- place. That drops its grants, which is why they're reapplied below exactly
-- as they were (see the GRANT statements in
-- 20260714180000_remote_schema.sql for the prior state).
DROP VIEW public.jobs_location_flags;

CREATE VIEW public.jobs_location_flags AS
WITH latest_snapshot AS (
  SELECT max(snapshot_date) AS latest FROM raw_watchlist_jobs
)
SELECT
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
    jc.raw,
    f.description_hash,
    jc.maybe_wa,
    jc.maybe_remote_wa,
    jc.discipline,
    jc.role_keyword,
    jc.level,
    wc.display_name,
    jc.first_seen,
    jc.current_version_first_seen AS description_last_change,
    jc.description_change_count,
    CASE
      WHEN jc.first_seen = ls.latest AND f.posted_at IS NOT NULL
           AND f.posted_at::date >= jc.first_seen - 1 THEN 'New'
      WHEN jc.first_seen = ls.latest AND f.posted_at IS NULL
                                                    THEN 'New*'
      WHEN jc.first_seen < ls.latest AND f.posted_at IS NOT NULL
           AND f.posted_at::date > jc.first_seen      THEN 'Reposted'
      ELSE NULL
    END AS post_status
   FROM raw_watchlist_jobs f
     LEFT JOIN job_content jc ON jc.watchlist_company = f.watchlist_company AND jc.ats_id = f.ats_id
     LEFT JOIN watchlist_companies wc ON wc.company = f.watchlist_company
     CROSS JOIN latest_snapshot ls;

GRANT SELECT, REFERENCES, TRIGGER, TRUNCATE ON public.jobs_location_flags TO anon;
GRANT SELECT, REFERENCES, TRIGGER, TRUNCATE ON public.jobs_location_flags TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.jobs_location_flags TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON public.jobs_location_flags TO postgres;

DROP TABLE public.target_filter_rules;
