-- ats_probe_latest wrongly assumed legacy rows have status IS NULL. They
-- don't: the July probe already wrote a status column with its own old
-- vocabulary ('ok', 'ok:dc-fixed', 'ok:retry', 'fail:ScraperError',
-- 'fail:JSONDecodeError', 'fail:CompanyNotFoundError' - all 522 rows, none
-- null). The 484 legacy 'ok' rows collided with the new vocabulary's 'ok'
-- and fell into the count-based scoring tree with sw_jobs/tech_jobs at 0,
-- landing on a meaningless Omit-* label instead of Unscored.
--
-- Switching the legacy discriminator from status IS NULL to a time
-- boundary: every legacy row was probed in July 2026, strictly before
-- 2026-07-22, and no future probe run (step 3+) can produce a probed_at
-- that old. sw_jobs IS NULL was considered and rejected - a genuine future
-- 'empty'/'error'/'gone' row also has null sw_jobs (those outcomes never
-- reach the counting logic), so that discriminator would misclassify them
-- as legacy too. probed_at doesn't have that collision.
create or replace view public.ats_probe_latest as
with latest as (
  select distinct on (lower(ats), lower(slug)) *
  from public.ats_probe_results
  order by lower(ats), lower(slug), probed_at desc
)
select
  l.ats,
  l.slug,
  l.company,
  l.url,
  l.status,
  l.probed_at,
  l.total_jobs,
  l.tech_jobs,
  l.sw_jobs,
  l.wa_jobs,
  l.bay_jobs,
  l.nyc_jobs,
  l.remote_wa_jobs,
  l.remote_ca_jobs,
  l.remote_ny_jobs,
  l.unmatched_locations,
  l.http_status,
  l.error_detail,
  (l.tech_jobs::numeric / nullif(l.total_jobs, 0)) as tech_pct,
  (l.sw_jobs::numeric / nullif(l.total_jobs, 0)) as software_pct,
  (coalesce(l.wa_jobs, 0) + coalesce(l.remote_wa_jobs, 0)) as local,
  (rec.seattle_rec).rec as seattle_rec,
  (rec.seattle_rec).note as seattle_rec_note,
  pd.reviewed,
  pd.add_to_watchlist,
  pd.decided_at,
  pd.notes
from latest l
left join public.probe_decisions pd
  on lower(pd.ats) = lower(l.ats) and lower(pd.slug) = lower(l.slug)
cross join lateral (
  select public._seattle_rec(
    l.ats,
    coalesce(l.total_jobs, 0),
    coalesce(l.sw_jobs, 0),
    (coalesce(l.sw_jobs, 0)::numeric / nullif(coalesce(l.total_jobs, 0), 0)),
    (coalesce(l.wa_jobs, 0) + coalesce(l.remote_wa_jobs, 0)) > 0,
    case when l.probed_at < timestamptz '2026-07-22' then 'legacy' else coalesce(l.status, 'ok') end
  ) as seattle_rec
) rec;

GRANT SELECT ON public.ats_probe_latest TO anon, authenticated, service_role, postgres;
