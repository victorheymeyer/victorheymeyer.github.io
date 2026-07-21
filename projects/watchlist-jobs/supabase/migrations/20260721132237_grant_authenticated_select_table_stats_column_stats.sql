-- Reconstructed from the live database: this migration was applied directly
-- via the Supabase MCP apply_migration tool on 2026-07-21 but the matching
-- file was never added to the repo. Recovered here for parity between the
-- migration history table and this folder; not re-applied (already live).
--
-- table_stats/column_stats were created with `grant select ... to anon` only
-- (see 20260717185309_create_table_stats_and_column_stats.sql). authenticated
-- sessions need the same read access as the stats views are exposed the same
-- way job_content/raw_watchlist_jobs are (see
-- 20260720195550_grant_authenticated_select_on_raw_jobs_and_job_content.sql).
--
-- TRUNCATE/TRIGGER/REFERENCES also show up for anon/authenticated on these
-- tables, but those are inherited from schema-level default privileges (the
-- same pattern appears on job_content, which only ever had SELECT explicitly
-- granted) — not something this migration added, and not reproduced here.
grant select on table_stats  to authenticated;
grant select on column_stats to authenticated;
