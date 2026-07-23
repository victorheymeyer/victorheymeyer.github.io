-- Make refresh_job_freshness algo-aware. current_description_hash is the
-- ONLY thing that writes this column (it's RPC-owned, not in the loader's
-- DIM_COLS), so a hashing-algorithm change (this migration is the first
-- case, jobhive-py -> ats-scrapers) has to be handled here or nowhere.
--
-- The single comparison becomes two: a same-algorithm hash difference still
-- bumps current_version_first_seen (a real content change). A hash_algo
-- difference -- including every existing row, where hash_algo is still
-- NULL before this migration -- adopts the new hash/algo as the baseline
-- WITHOUT touching current_version_first_seen or (via the loader's own
-- algo-aware check on hash_algo) description_change_count, since only the
-- hashing method changed, not the content. This lets every future
-- algorithm change self-heal on its own next run, with no cutover-night
-- script needed.
--
-- Accepted limitation: a genuine content change landing on the exact same
-- run as an algorithm switch is indistinguishable from the switch itself
-- and gets swallowed. One run's blind spot, not ongoing.
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
    -- baseline. Do not touch current_version_first_seen -- the content
    -- itself is not known to have changed, only the hashing method.
    update job_content c
    set current_description_hash = f.description_hash,
        hash_algo = f.hash_algo
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
