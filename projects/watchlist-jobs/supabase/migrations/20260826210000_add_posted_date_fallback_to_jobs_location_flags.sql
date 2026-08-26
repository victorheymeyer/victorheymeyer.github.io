-- Adds a display-time posted_date fallback chain to jobs_location_flags:
-- posted_at's Seattle day, else start_date (Workday's job-start date, already
-- a bare Seattle-sourced calendar day per 20260826200000 -- no AT TIME ZONE
-- conversion applied here, since that would shift a bare date back a day
-- (verified empirically: '2026-01-15'::date AT TIME ZONE 'America/Los_Angeles'
-- ::date = 2026-01-14, because the date implicitly casts to timestamptz at
-- UTC midnight before the zone conversion runs), else NULL for a job first
-- seen the same day its company joined the watchlist (no signal to fall back
-- on), else first_seen - 1 as the best guess for an established company.
--
-- This can only live in the view, not as a stored/trigger column on
-- job_content: it depends on is_new_company, which is itself only knowable
-- at query time (wc.company_first_seen compared against the latest snapshot,
-- which advances daily) -- freezing it into job_content would go stale the
-- day after a row is written.
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
  case
    when jc.posted_at is not null then (jc.posted_at at time zone 'America/Los_Angeles')::date
    when jc.start_date is not null then jc.start_date
    when (wc.company_first_seen is not null and wc.company_first_seen = ls.latest) then null
    else jc.first_seen - 1
  end as posted_date
from job_content jc
left join watchlist_companies wc on wc.company = jc.watchlist_company
cross join latest_snapshot ls
where jc.last_seen = ls.latest;
