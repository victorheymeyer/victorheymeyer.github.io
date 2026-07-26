-- Job.salary_period (HOUR/DAY/WEEK/MONTH/YEAR) was populated by the Ashby
-- and Lever scrapers (206 + 15 of our 292 active companies) but had no
-- column to land in, so it was silently dropped. salary_min/salary_max
-- were stored with no unit attached -- an hourly-rate posting's numbers
-- read identically to an annual salary in the job detail panel.
ALTER TABLE public.raw_watchlist_jobs
  ADD COLUMN salary_period text
  CHECK (salary_period IS NULL OR salary_period IN ('HOUR','DAY','WEEK','MONTH','YEAR'));

ALTER TABLE public.job_content
  ADD COLUMN salary_period text
  CHECK (salary_period IS NULL OR salary_period IN ('HOUR','DAY','WEEK','MONTH','YEAR'));
