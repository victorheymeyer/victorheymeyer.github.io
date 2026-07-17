create table if not exists table_stats (
  captured_date date        not null,
  table_name    text        not null,
  row_count     bigint,
  total_bytes   bigint,
  heap_bytes    bigint,
  toast_bytes   bigint,
  index_bytes   bigint,
  dead_tuples   bigint,
  min_data_date date,
  max_data_date date,
  captured_at   timestamptz not null default now(),
  primary key (captured_date, table_name)
);

create table if not exists column_stats (
  captured_date  date        not null,
  table_name     text        not null,
  column_name    text        not null,
  ordinal        int,
  data_type      text,
  non_null_count bigint,
  null_count     bigint,
  distinct_count bigint,
  total_bytes    bigint,
  avg_len        numeric,
  min_len        int,
  max_len        int,
  captured_at    timestamptz not null default now(),
  primary key (captured_date, table_name, column_name)
);

alter table table_stats  enable row level security;
alter table column_stats enable row level security;

create policy "public read table_stats"  on table_stats  for select to anon using (true);
create policy "public read column_stats" on column_stats for select to anon using (true);

grant select on table_stats  to anon;
grant select on column_stats to anon;
