create or replace view jobs_location_flags as
select
  f.snapshot_date,
  f.watchlist_company,
  f.ats_id,
  f.ats_type,
  f.title,
  f.location,
  f.is_remote,
  f.department,
  f.team,
  f.employment_type,
  f.salary_min,
  f.salary_max,
  f.salary_currency,
  f.posted_at,
  f.fetched_at,
  f.url,
  f.apply_url,
  jc.raw,
  f.description_hash,
  jc.maybe_wa,
  jc.maybe_remote_wa,
  jc.discipline,
  jc.role_keyword,
  jc.level,
  wc.display_name,
  exists (
    select 1 from target_filter_rules r
    where r.category = 'discipline' and r.value = jc.discipline
  )
  and exists (
    select 1 from target_filter_rules r
    where r.category = 'role' and r.value = coalesce(jc.role_keyword, '__unclassified__')
  )
  and exists (
    select 1 from target_filter_rules r
    where r.category = 'level' and r.value = jc.level
  ) as is_target_match,
  jc.first_seen,
  jc.description_last_change,
  jc.description_change_count
from raw_watchlist_jobs f
left join job_content jc on jc.watchlist_company = f.watchlist_company and jc.ats_id = f.ats_id
left join watchlist_companies wc on wc.company = f.watchlist_company;
