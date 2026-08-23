-- One row per (day, error_code) count, read straight off pull_failures --
-- outcome is a per-row column there already (populated by
-- classify_pull_error() in fetch_watchlist_jobs.py), so it's carried
-- through here rather than re-derived, avoiding a second place the
-- error_code -> outcome mapping could drift out of sync.
--
-- pull_failures is small and already pruned to 30 days, so a live
-- aggregating view is cheap -- no precompute table, no capture function,
-- no cron wiring needed.
--
-- security_invoker means this view enforces the querying role's own RLS
-- on pull_failures, which currently allows `authenticated` only (no
-- anon policy) -- so this view stays authenticated-only too, matching
-- the underlying table.
create or replace view public.pull_failures_daily_counts
with (security_invoker = true) as
select
  snapshot_date,
  coalesce(error_code, 'UNCLASSIFIED') as error_code,
  coalesce(outcome, 'UNCLASSIFIED') as outcome,
  count(*) as failure_count
from pull_failures
group by snapshot_date, coalesce(error_code, 'UNCLASSIFIED'), coalesce(outcome, 'UNCLASSIFIED');

grant select on public.pull_failures_daily_counts to authenticated;
