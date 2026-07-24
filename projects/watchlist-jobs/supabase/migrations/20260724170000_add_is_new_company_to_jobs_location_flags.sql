-- is_new_company flags jobs that were part of a company's very first scrape
-- (its first_seen equals that company's earliest first_seen across all its
-- jobs), separate from post_status = 'New'/'New*'. job_content is upsert-only
-- (fetch_watchlist_jobs.py never deletes from it, and no migration does
-- either), so MIN(first_seen) per company is stable and won't drift as jobs
-- close - no stored/backfilled column needed.
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
    END AS post_status,
    (jc.first_seen IS NOT NULL AND jc.first_seen = cfs.company_first_seen) AS is_new_company
   FROM raw_watchlist_jobs f
     LEFT JOIN job_content jc ON jc.watchlist_company = f.watchlist_company AND jc.ats_id = f.ats_id
     LEFT JOIN watchlist_companies wc ON wc.company = f.watchlist_company
     LEFT JOIN company_first_seen cfs ON cfs.watchlist_company = f.watchlist_company
     CROSS JOIN latest_snapshot ls;
