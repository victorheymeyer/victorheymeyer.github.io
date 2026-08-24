-- stats/index.html is a public page (anon key, no login) and now surfaces a
-- "# of Failures" KPI sourced from pull_failures_daily_counts. That view is
-- security_invoker over pull_failures, which until now only granted SELECT
-- to authenticated -- so anon visitors got a silent empty result (RLS
-- default-deny, not an error), making the KPI misleadingly show 0. Widen
-- read access to anon, matching the "public read <table>" pattern already
-- used for job_stats/table_stats/raw_watchlist_jobs/watchlist_companies.
drop policy if exists "authenticated read pull_failures" on public.pull_failures;

create policy "public read pull_failures" on public.pull_failures
  for select to anon, authenticated using (true);

grant select on public.pull_failures to anon;
grant select on public.pull_failures_daily_counts to anon;
