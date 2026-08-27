-- Replace post_status's first_seen/scrape-timing-based New/New*/Reposted
-- logic with a single posted_date-driven rule: New = the job's posted_date
-- (job_content.posted_date, already a Seattle-day date column with its own
-- fallback chain -- see 20260826220000_hardcode_job_content_posted_date.sql)
-- equals the latest snapshot's day minus one. No AT TIME ZONE conversion is
-- needed here: both ls.latest (from raw_watchlist_jobs.snapshot_date) and
-- jc.posted_date are already plain Seattle-calendar-day `date` values, not
-- timestamptz.
--
-- Anchored to ls.latest (the latest completed scrape), not now()/CURRENT_DATE
-- (wall clock), for consistency with the rest of this view and with
-- is_new_company -- see the "Cron limitation" note in CLAUDE.md: never treat
-- wall-clock/cron-trigger time as authoritative over the actual latest
-- snapshot.
--
-- New* and Reposted are deliberately dropped, not carried forward in any
-- form -- may be revisited later, but for now post_status is New/NULL only.
-- A NULL comparison (jc.posted_date IS NULL, e.g. a job from a company seen
-- for the first time today) naturally falls through to NULL/no badge with
-- no extra guard needed.
create or replace view public.jobs_location_flags as
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
    when jc.posted_date = ls.latest - 1 then 'New'
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

COMMENT ON VIEW public.jobs_location_flags IS
'If you CREATE OR REPLACE this view for an unrelated reason (e.g. adding a column), copy the post_status CASE expression byte-for-byte from the current definition first (SELECT pg_get_viewdef(''public.jobs_location_flags'', true)) rather than an older migration file. post_status is now posted_date-driven (see migration simplify_post_status_to_posted_date_only): New = jc.posted_date = ls.latest - 1, else NULL. It no longer depends on first_seen/scrape timing (that logic -- New*/Reposted -- was intentionally dropped, not preserved anywhere). Do not resurrect the old first_seen-based CASE without re-reading that migration.';

COMMENT ON COLUMN public.jobs_location_flags.post_status IS
'New = job_content.posted_date equals the latest snapshot day minus one (jc.posted_date = ls.latest - 1); everything else is NULL. posted_date is already a Seattle-calendar-day column with its own fallback chain (posted_at''s Seattle day, else start_date, else NULL for a brand-new company''s debut batch, else first_seen - 1) -- see 20260826220000_hardcode_job_content_posted_date.sql. Anchored to ls.latest (the latest completed scrape), not wall-clock now()/CURRENT_DATE, so a stalled scraper does not desync post_status from what was actually last captured. The prior New*/Reposted states were removed outright in migration simplify_post_status_to_posted_date_only, not folded into this value -- do not assume either string can still appear.';
