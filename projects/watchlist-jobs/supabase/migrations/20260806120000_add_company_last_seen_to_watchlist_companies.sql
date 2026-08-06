-- company_last_seen is company_first_seen's counterpart: the most recent
-- date any of a company's jobs was confirmed still present
-- (MAX(job_content.last_seen) per company), vs. company_first_seen's
-- earliest-date. Unlike first_seen, job_content.last_seen is NOT
-- write-once -- it advances every successful pull that returns that job --
-- so refresh_company_last_seen() must overwrite on every run, not just
-- fill NULLs like refresh_company_first_seen() does.
--
-- For a company that stops being scraped (deactivated, or a scraper that
-- starts erroring/returning empty), this value simply freezes at its last
-- successful pull date -- exactly the staleness signal used earlier to
-- spot cloudwalk/maven/russellinvestments.
alter table watchlist_companies add column company_last_seen date;

create or replace function refresh_company_last_seen()
returns void
language sql
as $$
  update watchlist_companies wc
  set company_last_seen = sub.last_seen
  from (
    select watchlist_company, max(last_seen) as last_seen
    from job_content
    group by watchlist_company
  ) sub
  where sub.watchlist_company = wc.company;
$$;

revoke execute on function refresh_company_last_seen() from public;
grant execute on function refresh_company_last_seen() to service_role;
