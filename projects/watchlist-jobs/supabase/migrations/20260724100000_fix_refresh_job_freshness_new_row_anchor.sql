-- Update B (the algorithm re-baseline branch added for the ats-scrapers
-- cutover) deliberately never touches current_version_first_seen, since an
-- algorithm change alone isn't a content change. But that also means any
-- row whose FIRST-EVER successful hash lands on a run where hash_algo
-- doesn't match yet -- true for every row before this migration, and true
-- going forward for any row whose description has simply never been
-- captured before (e.g. Eightfold's known flaky capture) -- takes Update B
-- on that first real hash and never gets a version anchor at all.
--
-- Fix: when Update B fires and the row has no anchor yet, give it one
-- (this is, after all, the first known version of this row's content).
-- Existing rows keep whatever anchor they already had -- coalesce only
-- fills the gap, it doesn't reset anything Update A already set correctly.
create or replace function public.refresh_job_freshness(run_date date) returns void
    language plpgsql
    as $$
begin
    update job_content
    set first_seen = run_date
    where first_seen is null;

    -- Same algorithm, hash differs: real content change.
    update job_content c
    set current_version_first_seen = run_date,
        current_description_hash = f.description_hash,
        hash_algo = f.hash_algo
    from (
        select watchlist_company, ats_id, description_hash, hash_algo
        from raw_watchlist_jobs
        where snapshot_date = run_date
    ) f
    where c.watchlist_company = f.watchlist_company
      and c.ats_id = f.ats_id
      and f.description_hash is not null
      and c.hash_algo is not distinct from f.hash_algo
      and c.current_description_hash is distinct from f.description_hash;

    -- Algorithm changed (or was never set): adopt the new hash/algo as the
    -- baseline. Do not overwrite an existing anchor -- the content itself
    -- is not known to have changed, only the hashing method -- but if this
    -- row has never had one, give it one now instead of leaving it
    -- permanently anchor-less.
    update job_content c
    set current_description_hash = f.description_hash,
        hash_algo = f.hash_algo,
        current_version_first_seen = coalesce(c.current_version_first_seen, run_date)
    from (
        select watchlist_company, ats_id, description_hash, hash_algo
        from raw_watchlist_jobs
        where snapshot_date = run_date
    ) f
    where c.watchlist_company = f.watchlist_company
      and c.ats_id = f.ats_id
      and f.description_hash is not null
      and c.hash_algo is distinct from f.hash_algo;
end;
$$;
