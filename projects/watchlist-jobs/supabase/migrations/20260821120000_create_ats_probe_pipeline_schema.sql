-- Company-discovery probe pipeline, step 1 of 4 (schema only). No writes to
-- the 522 existing ats_probe_results rows; all new columns are nullable.
--
-- Status vocabulary written by the probe (step 3, not yet implemented):
-- 'ok' | 'empty' | 'gone' | 'error'. Legacy rows predate this column's use
-- and have status = null; the view below coalesces null to 'legacy' so they
-- never fall into the count-based scoring tree (they'd score as meaningless
-- Yes/Maybe/Omit labels otherwise) and instead get 'Unscored'.

-- 1a: add missing columns to ats_probe_results. total_jobs and wa_jobs
-- already existed from the July run; everything else here is new.
alter table public.ats_probe_results
  add column if not exists tech_jobs int,
  add column if not exists sw_jobs int,
  add column if not exists bay_jobs int,
  add column if not exists nyc_jobs int,
  add column if not exists remote_wa_jobs int,
  add column if not exists remote_ca_jobs int,
  add column if not exists remote_ny_jobs int,
  add column if not exists unmatched_locations jsonb,
  add column if not exists http_status int,
  add column if not exists error_detail text;

-- 1b: human review state, separate from the raw append-mode probe log.
-- No role grants yet (deliberate omission - the write path/editor for this
-- table isn't defined until a later step; postgres/service_role can reach it
-- via the SQL editor in the meantime, matching how other tables in this repo
-- get their CRUD grants added in a dedicated follow-up migration once the
-- actual writer is known).
create table public.probe_decisions (
  ats text not null,
  slug text not null,
  reviewed bool not null default false,
  add_to_watchlist bool,
  decided_at timestamptz,
  notes text,
  primary key (ats, slug)
);

-- 1c: seattle_rec scoring, ported verbatim (thresholds included) from
-- seattle_rec() in probe_preview.py. Returned as a composite type rather
-- than a table-returning function so the view can pull it in as
-- (public._seattle_rec(...)).rec / .note.
create type public.probe_rec as (rec text, note text);

create or replace function public._seattle_rec(
  p_ats text,
  p_total int,
  p_sw_count int,
  p_sw_pct numeric,
  p_local_present boolean,
  p_outcome text
) returns public.probe_rec
language plpgsql
immutable
as $$
declare
  v_total int := coalesce(p_total, 0);
  v_sw int := coalesce(p_sw_count, 0);
  v_pct numeric := coalesce(p_sw_pct, 0);
  v_strong boolean;
  v_medium boolean;
  v_low boolean;
  v_capped boolean;
  result public.probe_rec;
begin
  -- Terminal outcomes first, mirroring the Python's "tried, won't auto-retry"
  -- states. 'legacy' is this migration's addition for pre-vocabulary rows.
  if p_outcome = 'error' then
    result.rec := 'Error';
    result.note := 'fetch error - recorded, will not auto-retry';
    return result;
  elsif p_outcome = 'gone' then
    result.rec := 'Gone';
    result.note := 'not on this ATS (migrated / slug changed)';
    return result;
  elsif p_outcome = 'empty' then
    result.rec := 'Empty';
    result.note := 'no listings (empty board) - done, no concern';
    return result;
  elsif p_outcome = 'legacy' then
    result.rec := 'Unscored';
    result.note := 'legacy row predates this scoring scheme - not yet re-probed';
    return result;
  end if;

  -- Unconditional zero/null-total guard (mirrors probe_preview.py's
  -- `if total == 0: return "Empty"`, which runs regardless of outcome).
  -- status should already be 'empty' whenever total_jobs is 0, but this
  -- keeps a status='ok' row with a null/zero total from falling into the
  -- count tree and misfiring a Yes/Maybe/Omit label off a division-by-zero
  -- that got silently zeroed by nullif().
  if v_total <= 0 then
    result.rec := 'Empty';
    result.note := 'no listings (empty board) - done, no concern';
    return result;
  end if;

  v_strong := (v_pct >= 0.10) or (v_sw >= 20);
  v_medium := (v_pct >= 0.05) or (v_sw >= 10);
  v_low    := (v_pct >= 0.01) or (v_sw >= 1);
  v_capped := lower(p_ats) = any(array['workday', 'smartrecruiters', 'eightfold']) and v_total > 50;

  -- 1. No local presence: a med-high software signal (>3%) earns a "watch",
  --    otherwise omit.
  if not coalesce(p_local_present, false) then
    if v_pct > 0.03 then
      result.rec := 'Maybe-later2';
      result.note := format('software %s%% but no Seattle/RemoteWA - watch', round(v_pct * 100)::int);
    else
      result.rec := 'Omit-NoLocal';
      result.note := 'no Seattle/RemoteWA roles (low software)';
    end if;
    return result;
  end if;

  -- 2. Giant board with a real software signal: accept but flag for review.
  if v_strong and v_total > 1000 then
    result.rec := 'Yes-Hold1';
    result.note := format('software ok (%s / %s%%) but big board (%s) - review', v_sw, round(v_pct * 100)::int, v_total);
    return result;
  end if;

  -- 3. Capped/paginated ATS with a real software signal: count may be understated.
  if v_strong and v_capped then
    result.rec := 'Yes-Hold2';
    result.note := format('software ok (%s / %s%%) on paginated ATS - review count', v_sw, round(v_pct * 100)::int);
    return result;
  end if;

  -- 4. Clean strong qualifier on a normal-size board: accept.
  if v_strong and v_total <= 1000 then
    result.rec := 'Yes-Go';
    result.note := format('strong software: %s jobs / %s%%', v_sw, round(v_pct * 100)::int);
    return result;
  end if;

  -- 5. Small company with local presence: always worth a quick look.
  if v_total < 100 then
    result.rec := 'Yes-SmallCoLowSW';
    result.note := format('small co (%s jobs), local present, low software (%s / %s%%) - quick review', v_total, v_sw, round(v_pct * 100)::int);
    return result;
  end if;

  -- 6. Medium signal: worth a look.
  if v_medium then
    result.rec := 'Maybe-Good';
    result.note := format('medium software: %s / %s%%', v_sw, round(v_pct * 100)::int);
    return result;
  end if;

  -- 7. Low signal: review only if you have time.
  if v_low then
    result.rec := 'Maybe-Low';
    result.note := format('low software: %s / %s%%', v_sw, round(v_pct * 100)::int);
    return result;
  end if;

  -- 8. Big board, local present, but essentially no software: omit.
  result.rec := 'Omit-NoSWjobs';
  result.note := format('big board (%s), ~no software (%s%%)', v_total, round(v_pct * 100)::int);
  return result;
end;
$$;

-- Latest row per (lower(ats), lower(slug)) from the append-mode probe log,
-- left-joined with human review state, plus derived percentages/local count
-- and the seattle_rec score.
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
    coalesce(l.status, 'legacy')
  ) as seattle_rec
) rec;

GRANT SELECT ON public.ats_probe_latest TO anon, authenticated, service_role, postgres;
