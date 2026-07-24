-- One-time repair for rows caught by the bug fixed in
-- 20260724100000_fix_refresh_job_freshness_new_row_anchor.sql: any row
-- whose first successful hash landed on a run where hash_algo didn't match
-- yet (every row touched by Update B before the coalesce fix existed) has
-- current_description_hash/hash_algo set but no current_version_first_seen.
--
-- Scoped to hash_algo is not null, NOT to "any null anchor with a
-- first_seen": a separate, larger population (~8,000 rows as of this
-- writing) has current_version_first_seen null AND hash_algo null,
-- meaning raw_watchlist_jobs has never had a successfully-hashed
-- description for them on any day (long-term scraper misses, e.g.
-- Eightfold's known flakiness, or boards they've since dropped off of).
-- That's a pre-existing characteristic unrelated to this migration, not a
-- bug this backfill should paper over by inventing a content baseline
-- where none has ever actually been established.
--
-- first_seen is the authoritative "row first appeared" anchor and was set
-- correctly throughout the cutover; using it here as the version anchor is
-- the same choice the OLD (pre-cutover) function made for a row's first
-- real hash, before Update B existed to intercept it.
update job_content
set current_version_first_seen = first_seen
where current_version_first_seen is null
  and hash_algo is not null;
