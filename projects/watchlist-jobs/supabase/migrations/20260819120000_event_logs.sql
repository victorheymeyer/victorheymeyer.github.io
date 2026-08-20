-- event_logs stores raw first-party telemetry (pageviews and clicks) written
-- directly from the browser beacon (telemetry.js) using the anon key.
--
-- Insert-only safety property: anon gets INSERT via both the RLS policy
-- below and the table GRANT (both are required, matching our other write
-- paths). There is no select/update/delete policy for anon, so those are
-- denied by default under RLS -- a malicious or compromised client can add
-- rows but can never read, modify, or delete any row, including one it just
-- wrote itself. Reads for analysis go through events_clean or the service
-- role, not through anon.

create table public.event_logs (
  id uuid primary key default gen_random_uuid(),
  event_type text not null check (event_type in ('pageview', 'click')),
  occurred_at timestamptz not null default now(),
  visitor_id text,
  session_id text,
  page_url text,
  referrer text,
  target_url text,
  watchlist_company text,
  ats_id text,
  user_agent text,
  ua_bot boolean,
  nav_webdriver boolean
);

alter table public.event_logs enable row level security;

create policy "anon can insert event_logs"
  on public.event_logs
  for insert
  to anon
  with check (true);

grant insert on public.event_logs to anon;

create view public.events_clean as
  select *
  from public.event_logs
  where coalesce(ua_bot, false) = false
    and coalesce(nav_webdriver, false) = false;
