-- Shift New/New* classification to fire the day after a job is first
-- captured, rather than same-day. Previously post_status compared
-- first_seen to ls.latest (today's run), so a job showed as New the
-- moment it was captured. That meant a manual workflow_dispatch run
-- during the day (e.g. an ad hoc afternoon pull) captured that day's
-- new postings early, leaving the following scheduled run with only a
-- short overnight window and few/no jobs left to mark New -- fragmenting
-- one day's worth of new postings across two days depending on run
-- timing.
--
-- Fix: classify New/New* off first_seen = ls.latest - 1 instead of
-- ls.latest. A job now shows as New/New* the day after its first
-- capture, once that whole calendar day's runs (however many, manual
-- or scheduled) have had a chance to record it. The Reposted branch is
-- unchanged -- it already excludes first_seen = ls.latest (today's
-- brand-new captures show no badge until tomorrow), and CASE order
-- still prefers New/New* over Reposted whenever both could apply.
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
