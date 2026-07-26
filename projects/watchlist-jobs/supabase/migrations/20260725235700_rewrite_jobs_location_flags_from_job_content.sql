-- jobs_location_flags no longer joins raw_watchlist_jobs at all. Every column
-- it used to pull from there now lives on job_content directly (see the two
-- migrations above), so this becomes a single filtered scan instead of a
-- 2-table join + 2 CTEs recomputed on every request. Confirmed via EXPLAIN:
-- this cut the view's query time from ~5.8s (recurring anon 3s-timeout
-- failures) to ~46ms.
--
-- Behavior change: "snapshot_date" is now an alias for job_content.last_seen
-- (this job's most recent scrape date), not a literal historical fact. Every
-- current caller already filters to the latest date only, so this is a no-op
-- for them - but this view can no longer answer "what did this look like on
-- an older snapshot_date" (only raw_watchlist_jobs can, and it isn't touched
-- by this view anymore). description_hash is dropped from the SELECT list -
-- verified unused by every consumer.
--
-- CREATE OR REPLACE VIEW can't drop a column, so this drops and recreates
-- the view; grants are reapplied to match what was there before (confirmed via
-- information_schema.role_table_grants: SELECT/TRUNCATE/REFERENCES/TRIGGER for
-- anon/authenticated, full set for service_role/postgres). security_invoker was
-- already off on the live view (checked pg_class.reloptions), so it's left off.
DROP VIEW public.jobs_location_flags;

CREATE VIEW public.jobs_location_flags AS
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
      WHEN jc.first_seen = ls.latest AND jc.posted_at IS NOT NULL
           AND jc.posted_at::date >= jc.first_seen - 1 THEN 'New'
      WHEN jc.first_seen = ls.latest AND jc.posted_at IS NULL
                                                    THEN 'New*'
      WHEN jc.first_seen < ls.latest AND jc.posted_at IS NOT NULL
           AND jc.posted_at::date > jc.first_seen      THEN 'Reposted'
      ELSE NULL
    END AS post_status,
    (jc.first_seen IS NOT NULL AND jc.first_seen = cfs.company_first_seen) AS is_new_company
   FROM job_content jc
     LEFT JOIN watchlist_companies wc ON wc.company = jc.watchlist_company
     LEFT JOIN company_first_seen cfs ON cfs.watchlist_company = jc.watchlist_company
     CROSS JOIN latest_snapshot ls
   WHERE jc.last_seen = ls.latest;

GRANT SELECT, TRUNCATE, REFERENCES, TRIGGER ON public.jobs_location_flags TO anon, authenticated;
GRANT INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.jobs_location_flags TO service_role, postgres;
