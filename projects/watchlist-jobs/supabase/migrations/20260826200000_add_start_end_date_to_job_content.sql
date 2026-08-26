-- Workday's job detail payload carries startDate/endDate as bare 'YYYY-MM-DD'
-- strings with no time or timezone component (see the upstream ats-scrapers
-- fork, commit 6a47697 "Workday: capture startDate/endDate from detail
-- payload into Job.raw" -- scratch clone at C:\Users\vheym\ats-scrapers, not
-- wired into the production scraper yet). No Seattle-day derivation applies
-- here, unlike posted_date (20260826190000): these dates aren't cast down
-- from a timestamptz, the source ATS hands them over as calendar dates
-- already.
alter table public.job_content
  add column start_date date,
  add column end_date date;
