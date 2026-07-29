-- Per-company, per-day checkpoint of a successful scrape+upsert, so a same-
-- day re-run (e.g. a manual workflow_dispatch retry after an unrelated
-- failure elsewhere in the run) can skip companies already loaded today
-- instead of re-scraping and re-upserting all ~35k rows again. That
-- redundant full-reload pattern is what tripled today's write churn into
-- job_content/raw_watchlist_jobs and bloated both past their vacuum
-- cadence -- see fetch_watchlist_jobs.py's already_done/pending split.
--
-- Granting select/insert/delete to service_role up front (not in three
-- separate follow-up migrations like pull_failures needed) since the loader
-- both reads this table (to build the skip set) and writes it.
create table if not exists public.pull_successes (
  snapshot_date     date        not null,
  watchlist_company text        not null,
  ats               text,
  job_count         integer     not null,
  created_at        timestamptz not null default now(),
  primary key (snapshot_date, watchlist_company)
);

alter table public.pull_successes enable row level security;

create policy "authenticated read pull_successes" on public.pull_successes
  for select to authenticated using (true);

grant select on public.pull_successes to authenticated;
grant select, insert, delete on public.pull_successes to service_role;
