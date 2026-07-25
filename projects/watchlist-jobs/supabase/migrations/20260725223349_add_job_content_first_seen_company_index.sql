-- jobs_location_flags' company_first_seen CTE runs MIN(first_seen) GROUP BY
-- watchlist_company over all of job_content on every query, with no supporting
-- index this was a full seq scan (~4.6s of the view's ~5.8s total). The anon
-- role's statement_timeout is only 3s, so this alone was enough to time out
-- the public site under any concurrent load.
CREATE INDEX IF NOT EXISTS idx_job_content_company_first_seen
  ON public.job_content (watchlist_company, first_seen)
  WHERE first_seen IS NOT NULL;
