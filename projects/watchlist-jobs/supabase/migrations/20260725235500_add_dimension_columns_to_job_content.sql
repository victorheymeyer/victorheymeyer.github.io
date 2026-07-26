-- job_content already carries most per-job fields (title, location, department,
-- url, apply_url, last_seen); these 8 are the only ones jobs_location_flags still
-- had to get from raw_watchlist_jobs. The scraper already computes all of them
-- every run (they're in FACT_COLS in fetch_watchlist_jobs.py) - they just were
-- never added to DIM_COLS.
ALTER TABLE public.job_content
  ADD COLUMN IF NOT EXISTS ats_type text,
  ADD COLUMN IF NOT EXISTS is_remote boolean,
  ADD COLUMN IF NOT EXISTS team text,
  ADD COLUMN IF NOT EXISTS employment_type text,
  ADD COLUMN IF NOT EXISTS salary_min numeric,
  ADD COLUMN IF NOT EXISTS salary_max numeric,
  ADD COLUMN IF NOT EXISTS salary_currency text,
  ADD COLUMN IF NOT EXISTS posted_at timestamptz;

-- Supports "WHERE last_seen = latest" in jobs_location_flags (see the view
-- rewrite migration below) - last_seen is set to snapshot_date on every
-- upsert, so this is exactly "jobs that appeared in the most recent scrape."
CREATE INDEX IF NOT EXISTS idx_job_content_last_seen
  ON public.job_content (last_seen);
