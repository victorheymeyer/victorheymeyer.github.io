-- posted_date is the Seattle calendar day derived from posted_at (timestamptz),
-- per this project's timezone invariant: every `date` column must be born from
-- the Seattle wall clock, never UTC. jobs_location_flags already computes this
-- ad hoc as (jc.posted_at at time zone 'America/Los_Angeles')::date for
-- post_status (20260806150000); this stores it directly on job_content instead.
--
-- Not a generated column: timezone(text, timestamptz) is STABLE, not IMMUTABLE
-- (tz database can change), so Postgres rejects it in a GENERATED ALWAYS AS
-- expression. A trigger keeps it in sync on insert/update instead.
alter table public.job_content
  add column posted_date date;

update public.job_content
set posted_date = (posted_at at time zone 'America/Los_Angeles')::date
where posted_at is not null;

create or replace function public.set_job_content_posted_date()
returns trigger
language plpgsql
as $$
begin
  new.posted_date := (new.posted_at at time zone 'America/Los_Angeles')::date;
  return new;
end;
$$;

create trigger job_content_set_posted_date
  before insert or update of posted_at on public.job_content
  for each row
  execute function public.set_job_content_posted_date();
