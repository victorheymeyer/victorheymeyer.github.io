-- The GRANT fix (previous migration) let authenticated touch these tables,
-- but RLS still blocked every row: both policies were scoped to {anon}
-- only, unlike watchlist_companies's equivalent policy which already
-- covers "authenticated", "anon". Widening to match that existing pattern.
alter policy "public read raw_watchlist_jobs" on public.raw_watchlist_jobs to anon, authenticated;
alter policy "public read job_content" on public.job_content to anon, authenticated;
