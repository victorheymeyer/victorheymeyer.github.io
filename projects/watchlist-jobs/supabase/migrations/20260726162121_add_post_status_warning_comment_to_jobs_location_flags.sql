-- Durable warning, attached to the view/column itself (survives any future
-- CREATE OR REPLACE VIEW, unlike a `--` comment inside the view body, which
-- Postgres strips at parse time -- this already bit us once: the
-- add_salary_period_to_jobs_location_flags_view migration recreated this
-- view from an older definition and silently reverted the day-shift fix
-- from shift_new_status_to_day_after_first_seen, requiring
-- reapply_new_status_day_shift_after_salary_period to fix it forward.
COMMENT ON VIEW public.jobs_location_flags IS
'If you CREATE OR REPLACE this view for an unrelated reason (e.g. adding a column), copy the post_status CASE expression byte-for-byte from the current definition first (SELECT pg_get_viewdef(''public.jobs_location_flags'', true)) rather than an older migration file. New/New* intentionally compares first_seen = (latest snapshot_date - 1), not = latest snapshot_date -- see migration shift_new_status_to_day_after_first_seen for why, and reapply_new_status_day_shift_after_salary_period for an incident where an unrelated view edit silently reverted it.';

COMMENT ON COLUMN public.jobs_location_flags.post_status IS
'New/New* = first_seen equals (latest snapshot_date - 1), i.e. the day AFTER a job was first captured, not the same day. This is deliberate: it lets one full calendar day''s runs (manual + scheduled) settle before showing new-job badges, so an ad hoc manual run mid-day cannot steal the following scheduled run''s New credit. Do not change back to "= latest" without re-reading migration shift_new_status_to_day_after_first_seen.';
