-- events_clean previously passed occurred_at straight through as the raw UTC
-- timestamptz from event_logs. Telemetry analysis is always done in Seattle
-- terms, so the view now converts occurred_at to the Seattle wall clock.
--
-- event_logs.occurred_at itself is untouched and stays UTC timestamptz per the
-- project timezone invariant; this is a read-side display transform only. The
-- resulting view column is `timestamp without time zone` holding
-- America/Los_Angeles local time (DST-aware). Because the column type changes,
-- the view has to be dropped and recreated rather than CREATE OR REPLACE'd.

drop view public.events_clean;

create view public.events_clean as
  select
    id,
    event_type,
    occurred_at at time zone 'America/Los_Angeles' as occurred_at,
    visitor_id,
    session_id,
    page_url,
    referrer,
    target_url,
    watchlist_company,
    ats_id,
    user_agent,
    ua_bot,
    nav_webdriver
  from public.event_logs
  where coalesce(ua_bot, false) = false
    and coalesce(nav_webdriver, false) = false;
