-- "Discipline" is being renamed to "Area" everywhere (DB + front-end) since
-- "Area" is the term actually used in conversation about this filter.
--
-- Renaming a table column does NOT cascade into a dependent view's output
-- column name -- a view's column names are fixed at CREATE VIEW time. The
-- jobs_location_flags view (which selects jc.discipline) still exposes
-- "discipline" after this and is fixed separately in
-- rename_jobs_location_flags_discipline_column_to_area.sql.
alter table public.job_content rename column discipline to area;

-- user_criteria.filters is a JSONB blob keyed by filter name (see
-- criteria.js). Existing saved rows have a "discipline" key that the
-- renamed front-end code will no longer look for; move it to "area" so
-- signed-in users don't lose their saved selection.
update public.user_criteria
set filters = (filters - 'discipline') || jsonb_build_object('area', filters->'discipline')
where filters ? 'discipline';
