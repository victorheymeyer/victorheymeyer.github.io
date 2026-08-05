-- is_new_company previously flagged any job whose OWN first_seen matched its
-- company's founding first_seen -- which stays true forever for that job as
-- long as it remains open, even weeks after the company was actually added
-- (e.g. salesforce__external_career_site, founded 2026-07-22, still showing
-- is_new_company=true on 2026-08-05 for jobs from that original batch that
-- never closed). The two consumers (index.html, my-jobs.html) only avoided
-- the bug by coincidence, since they always pair it with
-- post_status = 'New*' (which independently requires first_seen = today),
-- forcing the effective condition to already be "company_first_seen = today"
-- -- but the column itself was misleading on its own.
--
-- Correct definition: is_new_company should be true only when the company's
-- first-ever appearance IS the latest snapshot, i.e. it was actually just
-- added -- not a property of any individual job. Now reads the stored
-- watchlist_companies.company_first_seen column (see
-- 20260805140000_add_company_first_seen_to_watchlist_companies.sql) instead
-- of recomputing the same aggregate via a CTE.
create or replace view jobs_location_flags as
with latest_snapshot as (
  select max(snapshot_date) as latest from raw_watchlist_jobs
)
select
  jc.last_seen as snapshot_date,
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
  jc.current_version_first_seen as description_last_change,
  jc.description_change_count,
  case
    when jc.first_seen = ls.latest and jc.posted_at is not null and jc.posted_at::date >= (jc.first_seen - 1) then 'New'
    when jc.first_seen = ls.latest and jc.posted_at is null then 'New*'
    when jc.first_seen < ls.latest and jc.posted_at is not null and jc.posted_at::date > jc.first_seen then 'Reposted'
    else null
  end as post_status,
  (wc.company_first_seen is not null and wc.company_first_seen = ls.latest) as is_new_company,
  jc.salary_period
from job_content jc
left join watchlist_companies wc on wc.company = jc.watchlist_company
cross join latest_snapshot ls
where jc.last_seen = ls.latest;
