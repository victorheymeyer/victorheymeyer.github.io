-- job_stats' create-table migration only granted SELECT to anon/authenticated
-- and never granted service_role write access, so every capture_job_stats()
-- call (which runs as service_role) has failed with "permission denied for
-- table job_stats" since the table was created on 2026-07-30. Same pattern
-- as table_stats/column_stats, pull_failures, and pull_successes before it.
grant select, insert, update on public.job_stats to service_role;
