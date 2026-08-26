-- Persist six canonical ats_scrapers Job fields the loader already fetches
-- but previously dropped (not in DIM_COLS). All nullable; populated only for
-- rows whose source ATS exposes the field, null otherwise. Not backfilled;
-- fills forward from the next fetch_watchlist_jobs run.
alter table public.job_content
  add column if not exists country_iso    text,
  add column if not exists region         text,
  add column if not exists experience     integer,
  add column if not exists salary_summary text,
  add column if not exists commitment     text,
  add column if not exists language       text;
