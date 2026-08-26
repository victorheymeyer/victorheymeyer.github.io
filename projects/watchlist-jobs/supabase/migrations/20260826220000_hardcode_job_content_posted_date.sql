-- Switches job_content.posted_date from a posted_at-only trigger column to a
-- fully hard-coded column carrying the same fallback chain the previous
-- migration (20260826210000) added to jobs_location_flags: posted_at's
-- Seattle day, else start_date, else NULL for a job first seen the same day
-- its company joined the watchlist, else first_seen - 1.
--
-- Why not a trigger: the fallback needs is_new_company, i.e.
-- watchlist_companies.company_first_seen compared against "today's" run.
-- Per the pipeline in fetch_watchlist_jobs.py, job_content is upserted
-- BEFORE refresh_job_freshness() sets first_seen and BEFORE
-- refresh_company_first_seen() sets company_first_seen for a brand-new
-- company -- a row-level trigger firing mid-upsert would see stale/null
-- values for both and misclassify new-company jobs. Following the
-- refresh_job_freshness/refresh_company_first_seen/refresh_location_flags
-- pattern already used elsewhere in this table instead: an explicit
-- refresh_job_content_posted_date(run_date) function, called from the
-- Python pipeline once every other refresh step has finished for the run,
-- so company_first_seen and first_seen are guaranteed final before this
-- runs. It recomputes for every row (not just NULLs) because is_new_company
-- flips from true to false the day after a company's debut, so a job's
-- correct posted_date can change between runs even though nothing on the
-- row itself changed.
drop trigger if exists job_content_set_posted_date on public.job_content;
drop function if exists public.set_job_content_posted_date();

create or replace function public.refresh_job_content_posted_date(run_date date)
returns void
language sql
as $function$
  update job_content jc
  set posted_date = case
    when jc.posted_at is not null
      then (jc.posted_at at time zone 'America/Los_Angeles')::date
    when jc.start_date is not null
      then jc.start_date
    when (select wc.company_first_seen from watchlist_companies wc where wc.company = jc.watchlist_company) = run_date
      then null
    else jc.first_seen - 1
  end;
$function$;

revoke execute on function public.refresh_job_content_posted_date(date) from public;
grant execute on function public.refresh_job_content_posted_date(date) to service_role;
