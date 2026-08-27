-- Follow-up to 20260827120000: rename the Seattle-local column to
-- occurred_at_seattle and truncate it to whole seconds so it renders as
-- e.g. 2026-08-22 09:24:14 (no fractional part). Still a
-- `timestamp without time zone` in America/Los_Angeles wall-clock terms;
-- event_logs.occurred_at is untouched (UTC timestamptz per the timezone
-- invariant). Column rename means drop + recreate.

drop view public.events_clean;

create view public.events_clean as
  select
    id,
    event_type,
    date_trunc('second', occurred_at at time zone 'America/Los_Angeles') as occurred_at_seattle,
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
