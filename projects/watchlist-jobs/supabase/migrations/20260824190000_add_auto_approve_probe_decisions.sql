-- Auto-approve the two probe tiers that history shows are always decided
-- the same way: Yes-Go (51/51 approved) and Yes-SmallCoLowSW (82/83
-- approved, the one holdout being a name-collision edge case, not a tier
-- judgment call) in the 2026-08-22 run-2 batch review. Yes-Hold1/Yes-Hold2
-- stay manual - those had genuine mixed outcomes (declined for weak WA tie,
-- govt/defense contractor, etc.) that need a human read of the specifics.
--
-- SECURITY DEFINER so the caller (service_role, via probe_ats.py) doesn't
-- need direct table grants on probe_decisions - it only needs EXECUTE on
-- this one controlled entry point, matching the "no grants until the writer
-- is known" deferral from the schema migration (20260821120000).
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
