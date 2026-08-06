-- post_status compared jc.posted_at::date (an implicit cast through the
-- session timezone -- UTC on this project, confirmed via `SHOW timezone`)
-- against jc.first_seen (a Seattle-day column). A job posted between UTC
-- midnight and Seattle midnight would land on the wrong side of the
-- New/Reposted boundary. Converts posted_at to its Seattle calendar date
-- explicitly before comparing, matching the project's timezone invariant.
-- Only the two `::date` casts change from the current definition in
-- 20260805150000_fix_is_new_company_to_company_level.sql.
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
    when jc.first_seen = ls.latest and jc.posted_at is not null and (jc.posted_at at time zone 'America/Los_Angeles')::date >= (jc.first_seen - 1) then 'New'
    when jc.first_seen = ls.latest and jc.posted_at is null then 'New*'
    when jc.first_seen < ls.latest and jc.posted_at is not null and (jc.posted_at at time zone 'America/Los_Angeles')::date > jc.first_seen then 'Reposted'
    else null
  end as post_status,
  (wc.company_first_seen is not null and wc.company_first_seen = ls.latest) as is_new_company,
  jc.salary_period
from job_content jc
left join watchlist_companies wc on wc.company = jc.watchlist_company
cross join latest_snapshot ls
where jc.last_seen = ls.latest;
