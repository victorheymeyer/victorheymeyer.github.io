-- Closes the loop after auto_approve_probe_decisions() (20260824190000/
-- 20260824191500): that function only writes probe_decisions, it never
-- touched watchlist_companies (deliberate at the time - "auto-approve" and
-- "goes live on the site" were kept as separate steps). This adds the
-- promotion step, tracked via a new promoted_at column so it's idempotent
-- and doesn't depend on matching watchlist_companies' inconsistent
-- Workday-vs-everyone-else slug/company shape to detect "already done".
alter table public.probe_decisions
  add column if not exists promoted_at timestamptz;

-- Workday's watchlist_companies convention differs from every other ATS
-- (confirmed against live rows, e.g. slug="https://remitly.wd5.myworkdayjobs.com/remitly_careers",
-- company="remitly__remitly_careers"): company is the directory's short
-- "tenant/site" slug with "/" -> "__" (NOT the human display name - Workday
-- display names collide too often to be a safe primary key), and slug is
-- the full careers URL (ats_probe_latest.url), not the short directory
-- slug. Every other ATS uses the human company name as-is and the short
-- slug verbatim - both confirmed empirically against existing rows before
-- writing this, not assumed.
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
    insert into public.watchlist_companies as w (company, ats, slug, active, notes)
    select
      c.target_company, c.ats, c.target_slug, true,
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

grant execute on function public.promote_probe_decisions() to service_role;
