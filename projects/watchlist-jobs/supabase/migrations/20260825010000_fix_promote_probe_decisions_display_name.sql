-- promote_probe_decisions() (20260825000000) computed display_name (c.display_name,
-- sourced from ats_probe_latest.company) but never wrote it into watchlist_companies -
-- confirmed empirically: all 379 auto-promoted rows have display_name IS NULL. The
-- jobs_location_flags view passes wc.display_name straight through with no coalesce,
-- so these companies render their raw `company` value on the frontend instead - for
-- Workday that's the ugly tenant/site slug (e.g. "remitly__remitly_careers") rather
-- than the human name, which is what surfaced this as "wrong name in the first column
-- of the global.html jobs table" for some but not all companies.
create or replace function public.promote_probe_decisions()
returns table (out_ats text, out_slug text, out_company text, out_seattle_rec text, out_promoted boolean, out_reason text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with candidates as (
    select
      pd.ats,
      pd.slug,
      l.company as display_name,
      l.url,
      l.seattle_rec,
      case when lower(pd.ats) = 'workday' then lower(replace(pd.slug, '/', '__'))
           else coalesce(l.company, pd.slug) end as target_company,
      case when lower(pd.ats) = 'workday' then l.url else pd.slug end as target_slug
    from public.probe_decisions pd
    join public.ats_probe_latest l
      on lower(l.ats) = lower(pd.ats) and lower(l.slug) = lower(pd.slug)
    where pd.add_to_watchlist is true
      and pd.promoted_at is null
  ),
  inserted as (
    insert into public.watchlist_companies as w (company, display_name, ats, slug, active, notes)
    select
      c.target_company, c.display_name, c.ats, c.target_slug, true,
      format('Auto-promoted from probe pipeline, "%s" tier', c.seattle_rec)
    from candidates c
    where not exists (
      select 1 from public.watchlist_companies w2
      where lower(w2.company) = lower(c.target_company)
    )
    on conflict (company) do nothing
    returning w.company
  ),
  marked as (
    update public.probe_decisions pd
    set promoted_at = now()
    from candidates c
    where lower(pd.ats) = lower(c.ats) and lower(pd.slug) = lower(c.slug)
    returning pd.ats, pd.slug
  )
  select
    c.ats, c.slug, c.target_company, c.seattle_rec,
    (i.company is not null) as promoted,
    case when i.company is not null then null else 'company name collision with existing watchlist_companies row' end
  from candidates c
  join marked m on lower(m.ats) = lower(c.ats) and lower(m.slug) = lower(c.slug)
  left join inserted i on lower(i.company) = lower(c.target_company);
end;
$$;

-- Backfill the rows already promoted before this fix, using the same
-- ats/slug -> ats_probe_latest.company mapping the function itself uses.
-- Confirmed empirically before writing this: every target_company maps to
-- exactly one distinct display_name (no ambiguous backfill targets), and all
-- 379 pre-existing null rows have a mapping available.
with mapped as (
  select distinct
    case when lower(pd.ats) = 'workday' then lower(replace(pd.slug, '/', '__'))
         else coalesce(l.company, pd.slug) end as target_company,
    l.company as display_name
  from public.probe_decisions pd
  join public.ats_probe_latest l
    on lower(l.ats) = lower(pd.ats) and lower(l.slug) = lower(pd.slug)
  where pd.promoted_at is not null
)
update public.watchlist_companies w
set display_name = m.display_name
from mapped m
where lower(w.company) = lower(m.target_company)
  and w.display_name is null;
