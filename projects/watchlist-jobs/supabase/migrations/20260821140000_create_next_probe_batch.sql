-- Company-discovery probe pipeline, step 2 of 4: selection query only.
-- Read-only - selects from ats_company_directory / watchlist_companies /
-- ats_probe_results, writes nothing. The probe script (step 3) calls this
-- to get its work queue.
create or replace function public.next_probe_batch()
returns table (
  ats text,
  slug text,
  identifier text,
  company text,
  is_reprobe boolean
)
language sql
stable
as $$
  -- Must stay in sync with the step-3 scraper registry (ats_scrapers) and
  -- the per-ATS caps case below - adding/removing an ATS here means
  -- updating both.
  with enabled_ats as (
    select unnest(array[
      'greenhouse', 'ashby', 'workday', 'lever',
      'workable', 'smartrecruiters', 'rippling', 'eightfold'
    ]) as ats
  ),
  -- One row per (ats, slug) ever probed. properly_probed is true if any
  -- probe of this company happened on/after the 2026-07-22 cutoff - the
  -- same cutoff ats_probe_latest's legacy discriminator uses, so
  -- "legacy vs properly-probed" has one definition across the codebase.
  probe_status as (
    select
      lower(r.ats) as ats,
      lower(r.slug) as slug,
      bool_or(r.probed_at >= timestamptz '2026-07-22') as properly_probed
    from public.ats_probe_results r
    group by lower(r.ats), lower(r.slug)
  ),
  candidates as (
    select
      d.id,
      d.ats,
      d.slug,
      d.company,
      case when lower(d.ats) = 'workday' then d.url else d.slug end as identifier,
      -- Any row here that DID match probe_status is, by construction,
      -- legacy-only (properly-probed rows were already excluded below) -
      -- so ps.slug is not null IS "this is a reprobe".
      (ps.slug is not null) as is_reprobe,
      case when ps.slug is null then 0 else 1 end as sort_key
    from public.ats_company_directory d
    join enabled_ats ea on lower(d.ats) = ea.ats
    left join probe_status ps
      on ps.ats = lower(d.ats) and ps.slug = lower(d.slug)
    where not exists (
      select 1 from public.watchlist_companies w
      where lower(w.ats) = lower(d.ats) and lower(w.slug) = lower(d.slug)
    )
    and (ps.properly_probed is distinct from true)
  ),
  ranked as (
    select
      c.*,
      row_number() over (
        partition by lower(c.ats)
        order by c.sort_key, c.id asc
      ) as rn
    from candidates c
  )
  select ats, slug, identifier, company, is_reprobe
  from ranked
  where rn <= case
    when lower(ats) in ('workday', 'smartrecruiters', 'eightfold') then 20
    else 100
  end
  order by lower(ats), sort_key, id;
$$;
