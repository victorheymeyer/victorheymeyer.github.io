-- Existing job_content rows predate the columns added in the prior migration.
-- Backfill each job from its own latest raw_watchlist_jobs row (not just
-- today's snapshot), so jobs not in today's scrape still get a sensible
-- last-known value. Jobs whose last raw row has already aged out of
-- raw_watchlist_jobs' retention window are left null - harmless, since
-- jobs_location_flags only ever shows currently-active (last_seen = latest) rows.
UPDATE public.job_content jc
SET
  ats_type = f.ats_type,
  is_remote = f.is_remote,
  team = f.team,
  employment_type = f.employment_type,
  salary_min = f.salary_min,
  salary_max = f.salary_max,
  salary_currency = f.salary_currency,
  posted_at = f.posted_at
FROM (
  SELECT DISTINCT ON (watchlist_company, ats_id)
    watchlist_company, ats_id, ats_type, is_remote, team, employment_type,
    salary_min, salary_max, salary_currency, posted_at
  FROM public.raw_watchlist_jobs
  ORDER BY watchlist_company, ats_id, snapshot_date DESC
) f
WHERE f.watchlist_company = jc.watchlist_company
  AND f.ats_id = jc.ats_id;

VACUUM ANALYZE public.job_content;
