alter table job_content
  add column if not exists description_change_count integer not null default 0,
  add column if not exists description_last_change date;
