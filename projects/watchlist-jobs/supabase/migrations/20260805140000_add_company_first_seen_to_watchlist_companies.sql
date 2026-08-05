-- company_first_seen mirrors the company_first_seen CTE already computed
-- ad hoc inside the jobs_location_flags view (MIN(job_content.first_seen)
-- per company) -- materialized here as a real column on watchlist_companies
-- so it can be queried/joined directly without recomputing the aggregate.
--
-- job_content.first_seen is write-once (only ever set from NULL, see
-- refresh_job_freshness), so once a company's MIN(first_seen) lands here it
-- never needs to change -- refresh_company_first_seen() below only fills
-- NULLs, same pattern as refresh_job_freshness itself.
alter table watchlist_companies add column company_first_seen date;

create or replace function refresh_company_first_seen()
returns void
language sql
as $$
  update watchlist_companies wc
  set company_first_seen = sub.first_seen
  from (
    select watchlist_company, min(first_seen) as first_seen
    from job_content
    where first_seen is not null
    group by watchlist_company
  ) sub
  where sub.watchlist_company = wc.company
    and wc.company_first_seen is null;
$$;

revoke execute on function refresh_company_first_seen() from public;
grant execute on function refresh_company_first_seen() to service_role;

-- service_role previously had only SELECT/REFERENCES/TRIGGER/TRUNCATE on
-- watchlist_companies (see remote_schema.sql) -- no UPDATE, which is the
-- same gap that broke capture_job_stats(). Grant it now so
-- refresh_company_first_seen() can actually write.
grant update on watchlist_companies to service_role;
