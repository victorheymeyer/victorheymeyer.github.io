-- The prior grant (select, insert) missed the loader's 30-day retention
-- prune, which deletes from pull_failures as service_role -- that step was
-- failing with "permission denied for table pull_failures" even after the
-- select/insert grant landed.
grant delete on public.pull_failures to service_role;
