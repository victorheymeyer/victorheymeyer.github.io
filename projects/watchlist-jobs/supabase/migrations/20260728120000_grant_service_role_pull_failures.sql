-- The loader writes to pull_failures as service_role. RLS bypass for
-- service_role does not exempt it from the table-level GRANT system, and the
-- original migration only granted select to authenticated -- so every insert
-- from fetch_watchlist_jobs.py has been failing with "permission denied for
-- table pull_failures". Grant the loader's role what it actually needs.
grant select, insert on public.pull_failures to service_role;
