-- Added to speed up jobs_location_flags' old join against raw_watchlist_jobs.
-- That join no longer exists (see the view rewrite migration), and the one
-- remaining page that queries raw_watchlist_jobs directly
-- (tables/raw_watchlist_jobs.html) only ever fetches 10 rows, so it doesn't
-- need this. Reclaims ~150MB.
DROP INDEX IF EXISTS idx_raw_watchlist_jobs_snapshot_covering;
