-- Append post_status column to jobs_location_flags without dropping the view (preserves grants).
-- New/New* requires first_seen = latest snapshot; Reposted requires first_seen < latest.
-- Operators intentionally differ: >= (first_seen - 1) for New vs strict > for Reposted.
CREATE OR REPLACE VIEW public.jobs_location_flags AS
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
    (EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE r.category = 'discipline'::text AND r.value = jc.discipline)) AND (EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE r.category = 'role'::text AND r.value = COALESCE(jc.role_keyword, '__unclassified__'::text))) AND (EXISTS ( SELECT 1
           FROM target_filter_rules r
          WHERE r.category = 'level'::text AND r.value = jc.level)) AS is_target_match,
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
