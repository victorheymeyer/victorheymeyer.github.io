-- add_salary_period_to_jobs_location_flags_view (20260726153208) was
-- authored from the pre-fix view definition and its CREATE OR REPLACE
-- silently reverted the day-after-first-seen shift from
-- shift_new_status_to_day_after_first_seen / align_reposted_boundary_with_new_window.
-- Reapplying that fix here, now including jc.salary_period.
CREATE OR REPLACE VIEW public.jobs_location_flags AS
WITH latest_snapshot AS (
  SELECT max(snapshot_date) AS latest FROM raw_watchlist_jobs
),
company_first_seen AS (
  SELECT watchlist_company, min(first_seen) AS company_first_seen
  FROM job_content
  WHERE first_seen IS NOT NULL
  GROUP BY watchlist_company
)
SELECT
    jc.last_seen AS snapshot_date,
    jc.watchlist_company,
    jc.ats_id,
    jc.ats_type,
    jc.title,
    jc.location,
    jc.is_remote,
    jc.department,
    jc.team,
    jc.employment_type,
    jc.salary_min,
    jc.salary_max,
    jc.salary_currency,
    jc.posted_at,
    jc.fetched_at,
    jc.url,
    jc.apply_url,
    jc.raw,
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
      WHEN jc.first_seen = ls.latest - 1 AND jc.posted_at IS NOT NULL
           AND jc.posted_at::date >= jc.first_seen - 1 THEN 'New'
      WHEN jc.first_seen = ls.latest - 1 AND jc.posted_at IS NULL
                                                    THEN 'New*'
      WHEN jc.first_seen < ls.latest - 1 AND jc.posted_at IS NOT NULL
           AND jc.posted_at::date > jc.first_seen      THEN 'Reposted'
      ELSE NULL
    END AS post_status,
    (jc.first_seen IS NOT NULL AND jc.first_seen = cfs.company_first_seen) AS is_new_company,
    jc.salary_period
   FROM job_content jc
     LEFT JOIN watchlist_companies wc ON wc.company = jc.watchlist_company
     LEFT JOIN company_first_seen cfs ON cfs.watchlist_company = jc.watchlist_company
     CROSS JOIN latest_snapshot ls
   WHERE jc.last_seen = ls.latest;
