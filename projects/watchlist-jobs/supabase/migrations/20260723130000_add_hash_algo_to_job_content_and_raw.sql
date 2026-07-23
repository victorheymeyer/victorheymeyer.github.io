-- hash_algo tags which description normalization produced
-- description_hash / current_description_hash, so a future format change
-- (jobhive-py -> ats-scrapers was the first) can be told apart from a real
-- content edit by comparing hash_algo instead of assuming every mismatch is
-- new content. Populated by the ats-scrapers cutover backfill in the same
-- pass, so this doesn't need a second rewrite of every row later. No RPC
-- reads this column yet -- refresh_job_freshness is left untouched.
alter table job_content
  add column if not exists hash_algo text;

alter table raw_watchlist_jobs
  add column if not exists hash_algo text;
