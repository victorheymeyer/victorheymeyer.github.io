-- job_stats' read policy only covered role anon, unlike its sibling tables
-- (table_stats, watchlist_companies, raw_watchlist_jobs), which all cover
-- anon and authenticated. That gap meant every job_stats query silently
-- returned zero rows under RLS for signed-in visitors (200 OK, empty
-- result, no error), which is why the stats page's Key Metrics and Job
-- Stats panels rendered NaN/blank while running under an authenticated
-- session, even though the same queries worked fine for anonymous visitors.

drop policy "public read job_stats" on public.job_stats;

create policy "public read job_stats"
  on public.job_stats
  for select
  to anon, authenticated
  using (true);
