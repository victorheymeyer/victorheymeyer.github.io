-- Fix: refresh_job_content_posted_date() (added in 20260826220000) issues a
-- bare `UPDATE job_content SET posted_date = CASE ... END;` with no WHERE
-- clause. PostgREST rejects unqualified UPDATE/DELETE even when the statement
-- lives inside a SQL function called via RPC, so every scheduled run has been
-- dying here with:
--   postgrest.exceptions.APIError:
--   {'message': 'UPDATE requires a WHERE clause', 'code': '21000'}
-- (first failure: Actions run 2026-08-27, the delayed 19:50 UTC run -- the
-- migration landed after the prior day's successful run.)
--
-- The function is meant to recompute posted_date for *every* row each run
-- (is_new_company flips the day after a company's debut -- see the
-- 20260826220000 header), so the right fix is an explicit `where true`, matching
-- the pattern the sibling refresh_* functions already satisfy with real
-- predicates.
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
  end
  where true;  -- intentional full-table recompute; satisfies PostgREST's unqualified-UPDATE guard
$function$;

revoke execute on function public.refresh_job_content_posted_date(date) from public;
grant execute on function public.refresh_job_content_posted_date(date) to service_role;
