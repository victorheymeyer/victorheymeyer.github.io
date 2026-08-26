-- job_content.ats_type was backfilled once already in
-- 20260725235600_backfill_job_content_dimension_columns.sql, sourced from
-- raw_watchlist_jobs.ats_type. That column was later dropped from
-- raw_watchlist_jobs in 20260728140000_drop_unused_raw_watchlist_jobs_columns.sql,
-- and any job_content row whose last raw_watchlist_jobs match had no
-- ats_type at backfill time (or was fetched before ats_type existed at all)
-- was left null - 8,223 rows across ~270 companies, discovered via
-- job-detail.js and stats/ats.html showing "N/A" / "(unknown)" ATS for jobs
-- known to belong to a single-ATS company (e.g. spacex, anthropic on
-- greenhouse).
--
-- ats_type is per-company here, not per-job: verified before running this
-- that no job_content row's non-null ats_type ever disagrees with its
-- company's watchlist_companies.ats, so backfilling every remaining null
-- from the config table is safe. Ran manually against prod on 2026-08-26
-- (8,223 rows updated, 0 null ats_type rows remaining); this migration
-- documents that change and reproduces it on any fresh restore.
UPDATE public.job_content jc
SET ats_type = wc.ats
FROM public.watchlist_companies wc
WHERE wc.company = jc.watchlist_company
  AND jc.ats_type IS NULL
  AND wc.ats IS NOT NULL;
