-- Tracks per-company scraper failures across daily runs so recurring
-- flakiness (e.g. one Workday tenant failing repeatedly over a week) is
-- visible without digging through GitHub Actions logs. Written by the
-- loader (service role, bypasses RLS) whenever a company pull fails or is
-- skipped for an unknown ats -- see fetch_watchlist_jobs.py.
create table if not exists public.pull_failures (
  id                bigint generated always as identity primary key,
  snapshot_date     date        not null,
  watchlist_company text        not null,
  ats               text,
  error_message     text,
  created_at        timestamptz not null default now()
);

create index if not exists pull_failures_company_date_idx
  on public.pull_failures (watchlist_company, snapshot_date);

alter table public.pull_failures enable row level security;

create policy "authenticated read pull_failures" on public.pull_failures
  for select to authenticated using (true);

grant select on public.pull_failures to authenticated;
