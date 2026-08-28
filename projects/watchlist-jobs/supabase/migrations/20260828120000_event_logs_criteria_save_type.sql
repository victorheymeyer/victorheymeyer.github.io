-- Widen event_logs.event_type beyond the browser beacon's 'pageview'/'click'
-- to cover explicit first-party UI actions. First use: 'criteria_save',
-- emitted by my-criteria.html's Save Criteria button via window.thTrack()
-- (telemetry.js). No RLS change needed -- the anon insert policy is
-- `with check (true)`, so this CHECK constraint was the only gate. The
-- events_clean view selects explicit columns and only filters bots, so the
-- new type flows through it unchanged.

alter table public.event_logs
  drop constraint event_logs_event_type_check;

alter table public.event_logs
  add constraint event_logs_event_type_check
  check (event_type in ('pageview', 'click', 'criteria_save'));
