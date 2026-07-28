-- raw_watchlist_jobs is a daily fact snapshot; these 12 columns duplicate
-- job_content but are never read back from raw_watchlist_jobs by any view,
-- RPC, or page (jobs_location_flags reads only max(snapshot_date) from it).
-- Keeping title/location/posted_at (the fields most plausibly worth a future
-- day-over-day diff, mirroring description_change_count) plus the key
-- columns and description_hash/hash_algo (read by refresh_job_freshness).
ALTER TABLE public.raw_watchlist_jobs
  DROP COLUMN department,
  DROP COLUMN url,
  DROP COLUMN apply_url,
  DROP COLUMN is_remote,
  DROP COLUMN team,
  DROP COLUMN employment_type,
  DROP COLUMN salary_min,
  DROP COLUMN salary_max,
  DROP COLUMN salary_currency,
  DROP COLUMN salary_period,
  DROP COLUMN ats_type,
  DROP COLUMN fetched_at;
