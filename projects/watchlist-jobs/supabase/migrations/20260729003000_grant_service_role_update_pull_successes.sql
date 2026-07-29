-- upsert() on pull_successes compiles to INSERT ... ON CONFLICT DO UPDATE,
-- which needs UPDATE privilege in addition to INSERT -- missed in the
-- original create_pull_successes grant, caught by an actual manual run
-- (loader degraded gracefully per the same migration's other fix, instead
-- of crashing the run).
grant update on public.pull_successes to service_role;
