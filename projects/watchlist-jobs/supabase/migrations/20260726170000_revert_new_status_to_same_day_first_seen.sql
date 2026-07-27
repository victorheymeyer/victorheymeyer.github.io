-- Revert New/New* classification to same-day (first_seen = ls.latest),
-- undoing the day-after shift from shift_new_status_to_day_after_first_seen
-- / align_reposted_boundary_with_new_window / reapply_new_status_day_shift_after_salary_period.
--
-- That shift traded same-day badges for run-timing independence: a job's
-- New badge would appear consistently the day after capture regardless of
-- how many manual/scheduled runs touched it during the day. In practice
-- this meant a job was never marked New on the day it was actually first
-- seen -- always a day late -- which is the behavior we actually want to
-- avoid. Reverting: New/New* now fires the moment first_seen equals the
-- latest snapshot date again, same as the original
-- add_post_status_to_jobs_location_flags definition. The Reposted boundary
-- reverts to < ls.latest (its original pairing) accordingly.
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
      WHEN jc.first_seen = ls.latest AND jc.posted_at IS NOT NULL
           AND jc.posted_at::date >= jc.first_seen - 1 THEN 'New'
      WHEN jc.first_seen = ls.latest AND jc.posted_at IS NULL
                                                    THEN 'New*'
      WHEN jc.first_seen < ls.latest AND jc.posted_at IS NOT NULL
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

COMMENT ON VIEW public.jobs_location_flags IS
'If you CREATE OR REPLACE this view for an unrelated reason (e.g. adding a column), copy the post_status CASE expression byte-for-byte from the current definition first (SELECT pg_get_viewdef(''public.jobs_location_flags'', true)) rather than an older migration file. New/New* compares first_seen = latest snapshot_date (same-day) -- see migration revert_new_status_to_same_day_first_seen. An earlier day-after variant (shift_new_status_to_day_after_first_seen) was tried and reverted; do not reintroduce it without discussing the tradeoff first.';

COMMENT ON COLUMN public.jobs_location_flags.post_status IS
'New/New* = first_seen equals the latest snapshot_date (same day a job is first captured). A prior version delayed this by one day (first_seen = latest - 1) to decouple the badge from run timing, but that meant a job was never New on the day it was actually first seen -- reverted in migration revert_new_status_to_same_day_first_seen. Do not reintroduce the day-after delay without re-discussing the tradeoff.';
