-- description_last_change duplicated the pre-existing current_version_first_seen
-- (verified byte-identical on every changed row): both mark the date the
-- currently-active description hash first appeared. current_version_first_seen
-- is maintained by refresh_job_freshness(); description_last_change was a
-- second, separately-written copy of the same fact. Consolidate onto the
-- original column and keep the external name stable via a view alias.
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
  jc.current_version_first_seen as description_last_change,
  jc.description_change_count
from raw_watchlist_jobs f
left join job_content jc on jc.watchlist_company = f.watchlist_company and jc.ats_id = f.ats_id
left join watchlist_companies wc on wc.company = f.watchlist_company;

alter table job_content drop column if exists description_last_change;
