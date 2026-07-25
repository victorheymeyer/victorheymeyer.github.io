-- After the company_first_seen index above, the remaining cost in
-- jobs_location_flags was the snapshot_date-filtered scan of raw_watchlist_jobs:
-- idx_raw_watchlist_jobs_snapshot_date is a plain (non-covering) index, so every
-- matching row needed a heap fetch. Under a cold cache this took ~1.9s on its
-- own - still too close to the anon role's 3s statement_timeout. This covering
-- index lets that scan be answered index-only, cutting the warm-cache view
-- query to ~270ms.
CREATE INDEX IF NOT EXISTS idx_raw_watchlist_jobs_snapshot_covering
  ON public.raw_watchlist_jobs (snapshot_date)
  INCLUDE (watchlist_company, ats_id, ats_type, title, location, is_remote,
           department, team, employment_type, salary_min, salary_max, salary_currency,
           posted_at, fetched_at, url, apply_url, description_hash, hash_algo);
