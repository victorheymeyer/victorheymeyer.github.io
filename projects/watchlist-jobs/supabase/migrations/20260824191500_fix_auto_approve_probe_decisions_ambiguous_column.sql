-- Fix ambiguous-column error in auto_approve_probe_decisions() (20260824190000):
-- PL/pgSQL treats bare "ats"/"slug" as the function's own OUT parameters
-- once they share a name with a RETURNS TABLE column, which collided with
-- the identically-named table columns inside the CTE/INSERT and broke the
-- RETURNING clause. Renaming the OUT columns (out_ats/out_slug/out_company/
-- out_seattle_rec) removes the collision entirely; the INSERT target is
-- also aliased (pd) and its RETURNING/ON CONFLICT clauses fully qualified,
-- belt-and-suspenders against the same class of bug reappearing.
--
-- CREATE OR REPLACE can't change a function's OUT-parameter row type, so
-- the old signature must be dropped first.
drop function if exists public.auto_approve_probe_decisions();

create or replace function public.auto_approve_probe_decisions()
returns table (out_ats text, out_slug text, out_company text, out_seattle_rec text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with to_approve as (
    select l.ats, l.slug, l.company, l.seattle_rec
    from public.ats_probe_latest l
    where l.seattle_rec in ('Yes-Go', 'Yes-SmallCoLowSW')
      and l.reviewed is not true
  ),
  upserted as (
    insert into public.probe_decisions as pd (ats, slug, reviewed, add_to_watchlist, decided_at, notes)
    select a.ats, a.slug, true, true, now(), format('Auto-approved - "%s" tier', a.seattle_rec)
    from to_approve a
    on conflict (ats, slug) do update
      set reviewed = true,
          add_to_watchlist = true,
          decided_at = now(),
          notes = excluded.notes
      where pd.reviewed is not true
    returning pd.ats, pd.slug
  )
  select a.ats, a.slug, a.company, a.seattle_rec
  from to_approve a
  join upserted u on u.ats = a.ats and u.slug = a.slug;
end;
$$;

grant execute on function public.auto_approve_probe_decisions() to service_role;
