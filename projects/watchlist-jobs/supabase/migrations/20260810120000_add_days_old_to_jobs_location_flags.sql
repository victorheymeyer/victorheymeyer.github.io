-- "Days old" was previously computed client-side, independently, in four
-- different places (index.html, global.html, my-jobs.html, job-detail.js) --
-- and they'd drifted: global.html only looked at posted_at (showing "-" for
-- every Workday job, which never has an absolute posted_at), while the
-- others fell back to first_seen when posted_at was null. Moving the single
-- definition here so every page reads the same number.
--
-- Per the project's timezone invariant, every `date` value is born from the
-- Seattle wall clock, never UTC. days_old is therefore a Seattle-calendar-day
-- difference, not a rolling 24h window: posted_at (timestamptz) is bucketed
-- to its Seattle calendar date before diffing against "today" in Seattle.
-- first_seen is already a Seattle calendar date, so it's used as-is.
--
-- days_old_estimated is true when posted_at is null and the value shown is
-- actually first_seen (the day our pipeline first observed the job, an
-- honest "discovered" signal, not a substitute posted date).
--
-- Only the new `days_old` / `days_old_estimated` columns change from the
-- view definition in 20260806150000_fix_jobs_location_flags_posted_at_seattle_date.sql.
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
  jc.salary_period,
  case
    when jc.posted_at is not null then
      greatest(0, (now() at time zone 'America/Los_Angeles')::date - (jc.posted_at at time zone 'America/Los_Angeles')::date)
    when jc.first_seen is not null then
      greatest(0, (now() at time zone 'America/Los_Angeles')::date - jc.first_seen)
    else null
  end as days_old,
  (jc.posted_at is null and jc.first_seen is not null) as days_old_estimated
from job_content jc
left join watchlist_companies wc on wc.company = jc.watchlist_company
cross join latest_snapshot ls
where jc.last_seen = ls.latest;
