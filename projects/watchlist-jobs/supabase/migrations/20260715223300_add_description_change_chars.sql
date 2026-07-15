alter table job_content
  add column if not exists description_last_change_chars integer,
  add column if not exists description_plain_len integer;
