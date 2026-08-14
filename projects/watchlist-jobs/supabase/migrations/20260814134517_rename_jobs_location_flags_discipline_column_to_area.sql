-- Renaming job_content.discipline to area (see rename_discipline_to_area)
-- did NOT cascade into the jobs_location_flags view's output column name --
-- a view's column names are fixed at CREATE VIEW time, not re-derived from
-- the source table on every query. Rename the view's own column explicitly.
alter view public.jobs_location_flags rename column discipline to area;
