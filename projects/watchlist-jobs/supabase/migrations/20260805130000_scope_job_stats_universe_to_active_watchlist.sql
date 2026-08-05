-- v_universe previously counted every company that has EVER appeared in
-- job_content (410 as of 2026-08-05), including ~119 companies since
-- deactivated in watchlist_companies whose stale rows never get deleted
-- (job_content is upsert-only). That inflated both
-- company_count_zero_active_jobs_global and company_count_zero_new_jobs_global
-- (they share this same universe CTE) with companies nobody is tracking
-- anymore. Scope the universe to active watchlist companies (291) instead,
-- matching company_count_watchlist_active_pull.
create or replace function capture_job_stats()
returns void
language plpgsql
as $$
declare
  v_today date := (now() at time zone 'utc')::date;
begin
  insert into job_stats (
    snapshot_date,
    company_count_watchlist_active_pull,
    company_count_zero_active_jobs_global,
    company_count_any_active_jobs_global,
    company_count_any_active_jobs_seattle,
    company_count_any_active_jobs_remote_wa,
    company_count_any_active_jobs_seattle_or_remote_wa,
    company_count_zero_new_jobs_global,
    company_count_any_new_jobs_global,
    company_count_any_new_jobs_seattle,
    company_count_any_new_jobs_remote_wa,
    company_count_any_new_jobs_seattle_or_remote_wa,
    company_count_any_new_jobs_seattle_and_remote_wa,
    job_count_active_global,
    job_count_active_seattle,
    job_count_active_remote_wa,
    job_count_active_seattle_or_remote_wa,
    job_count_new_global,
    job_count_new_seattle,
    job_count_new_remote_wa,
    job_count_new_seattle_or_remote_wa,
    job_count_new_seattle_and_remote_wa
  )
  select
    v_today,
    (select count(*) from watchlist_companies where active),
    v_universe.n - v_active.any_global,
    v_active.any_global,
    v_active.any_seattle,
    v_active.any_remote,
    v_active.any_seattle_or_remote,
    v_universe.n - v_new.any_global,
    v_new.any_global,
    v_new.any_seattle,
    v_new.any_remote,
    v_new.any_seattle_or_remote,
    v_new.any_seattle_and_remote,
    v_jobs_active.global,
    v_jobs_active.seattle,
    v_jobs_active.remote,
    v_jobs_active.seattle_or_remote,
    v_jobs_new.global,
    v_jobs_new.seattle,
    v_jobs_new.remote,
    v_jobs_new.seattle_or_remote,
    v_jobs_new.seattle_and_remote
  from
    (select count(*) as n from watchlist_companies where active) v_universe,
    (
      select
        count(distinct watchlist_company) as any_global,
        count(distinct watchlist_company) filter (where maybe_wa) as any_seattle,
        count(distinct watchlist_company) filter (where maybe_remote_wa) as any_remote,
        count(distinct watchlist_company) filter (where maybe_wa or maybe_remote_wa) as any_seattle_or_remote
      from jobs_location_flags
    ) v_active,
    (
      select
        count(distinct watchlist_company) filter (where post_status in ('New','New*')) as any_global,
        count(distinct watchlist_company) filter (where post_status in ('New','New*') and maybe_wa) as any_seattle,
        count(distinct watchlist_company) filter (where post_status in ('New','New*') and maybe_remote_wa) as any_remote,
        count(distinct watchlist_company) filter (where post_status in ('New','New*') and (maybe_wa or maybe_remote_wa)) as any_seattle_or_remote,
        count(distinct watchlist_company) filter (where post_status in ('New','New*') and maybe_wa and maybe_remote_wa) as any_seattle_and_remote
      from jobs_location_flags
    ) v_new,
    (
      select
        count(*) as global,
        count(*) filter (where maybe_wa) as seattle,
        count(*) filter (where maybe_remote_wa) as remote,
        count(*) filter (where maybe_wa or maybe_remote_wa) as seattle_or_remote
      from jobs_location_flags
    ) v_jobs_active,
    (
      select
        count(*) filter (where post_status in ('New','New*')) as global,
        count(*) filter (where post_status in ('New','New*') and maybe_wa) as seattle,
        count(*) filter (where post_status in ('New','New*') and maybe_remote_wa) as remote,
        count(*) filter (where post_status in ('New','New*') and (maybe_wa or maybe_remote_wa)) as seattle_or_remote,
        count(*) filter (where post_status in ('New','New*') and maybe_wa and maybe_remote_wa) as seattle_and_remote
      from jobs_location_flags
    ) v_jobs_new
  on conflict (snapshot_date) do update set
    company_count_watchlist_active_pull = excluded.company_count_watchlist_active_pull,
    company_count_zero_active_jobs_global = excluded.company_count_zero_active_jobs_global,
    company_count_any_active_jobs_global = excluded.company_count_any_active_jobs_global,
    company_count_any_active_jobs_seattle = excluded.company_count_any_active_jobs_seattle,
    company_count_any_active_jobs_remote_wa = excluded.company_count_any_active_jobs_remote_wa,
    company_count_any_active_jobs_seattle_or_remote_wa = excluded.company_count_any_active_jobs_seattle_or_remote_wa,
    company_count_zero_new_jobs_global = excluded.company_count_zero_new_jobs_global,
    company_count_any_new_jobs_global = excluded.company_count_any_new_jobs_global,
    company_count_any_new_jobs_seattle = excluded.company_count_any_new_jobs_seattle,
    company_count_any_new_jobs_remote_wa = excluded.company_count_any_new_jobs_remote_wa,
    company_count_any_new_jobs_seattle_or_remote_wa = excluded.company_count_any_new_jobs_seattle_or_remote_wa,
    company_count_any_new_jobs_seattle_and_remote_wa = excluded.company_count_any_new_jobs_seattle_and_remote_wa,
    job_count_active_global = excluded.job_count_active_global,
    job_count_active_seattle = excluded.job_count_active_seattle,
    job_count_active_remote_wa = excluded.job_count_active_remote_wa,
    job_count_active_seattle_or_remote_wa = excluded.job_count_active_seattle_or_remote_wa,
    job_count_new_global = excluded.job_count_new_global,
    job_count_new_seattle = excluded.job_count_new_seattle,
    job_count_new_remote_wa = excluded.job_count_new_remote_wa,
    job_count_new_seattle_or_remote_wa = excluded.job_count_new_seattle_or_remote_wa,
    job_count_new_seattle_and_remote_wa = excluded.job_count_new_seattle_and_remote_wa,
    captured_at = now();
end;
$$;
