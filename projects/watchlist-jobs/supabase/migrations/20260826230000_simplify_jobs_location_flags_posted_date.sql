-- posted_date is now a hard-coded column on job_content (20260826220000),
-- kept in sync by refresh_job_content_posted_date() after every pipeline
-- run. The view previously recomputed the same fallback chain independently
-- -- duplicate logic under the same name that could silently drift from the
-- table. Pass jc.posted_date straight through instead.
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
  jc.area,
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
  jc.salary_period,
  case
    when jc.posted_at is not null then greatest(0, (now() at time zone 'America/Los_Angeles')::date - (jc.posted_at at time zone 'America/Los_Angeles')::date)
    when jc.first_seen is not null then greatest(0, (now() at time zone 'America/Los_Angeles')::date - jc.first_seen)
    else null
  end as days_old,
  (jc.posted_at is null and jc.first_seen is not null) as days_old_estimated,
  jc.posted_date
from job_content jc
left join watchlist_companies wc on wc.company = jc.watchlist_company
cross join latest_snapshot ls
where jc.last_seen = ls.latest;
