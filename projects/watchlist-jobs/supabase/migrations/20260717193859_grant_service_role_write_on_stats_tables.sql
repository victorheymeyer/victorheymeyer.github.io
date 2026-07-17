-- service_role has no table-level grants by default in this project (only
-- the RLS bypass), so the nightly capture script needs this explicitly or
-- every insert/update against table_stats/column_stats fails with
-- "permission denied for table ...".
grant select, insert, update on table_stats  to service_role;
grant select, insert, update on column_stats to service_role;
