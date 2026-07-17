drop function if exists capture_table_stats(text, text);

create function capture_table_stats(
  p_table         text,
  p_date_col      text    default null,
  p_filter_column text    default null,
  p_filter_value  boolean default null,
  p_stats_name    text    default null,
  p_columns_only  boolean default false
)
returns void
language plpgsql
as $$
declare
  v_reg   regclass := p_table::regclass;
  v_name  text := coalesce(p_stats_name, p_table);
  v_where text := case when p_filter_column is not null
                       then format(' where %I = %L', p_filter_column, p_filter_value)
                       else '' end;
  v_today date := (now() at time zone 'utc')::date;
  v_rows  bigint;
  v_total bigint; v_heap bigint; v_index bigint; v_toast bigint; v_dead bigint;
  v_mind  date; v_maxd date;
  v_col   record;
  v_nonnull bigint; v_bytes bigint; v_distinct bigint;
  v_avg numeric; v_min int; v_max int;
begin
  execute format('select count(*) from %s%s', v_reg, v_where) into v_rows;

  if not p_columns_only then
    v_total := pg_total_relation_size(v_reg);
    v_heap  := pg_relation_size(v_reg);
    v_index := pg_indexes_size(v_reg);
    v_toast := v_total - v_heap - v_index;

    select n_dead_tup into v_dead
      from pg_stat_user_tables where relid = v_reg;
  end if;

  if p_date_col is not null then
    execute format('select min(%I)::date, max(%I)::date from %s%s',
                   p_date_col, p_date_col, v_reg, v_where)
      into v_mind, v_maxd;
  end if;

  insert into table_stats(
    captured_date, table_name, row_count, total_bytes, heap_bytes,
    toast_bytes, index_bytes, dead_tuples, min_data_date, max_data_date)
  values (v_today, v_name, v_rows, v_total, v_heap,
          v_toast, v_index, v_dead, v_mind, v_maxd)
  on conflict (captured_date, table_name) do update set
    row_count=excluded.row_count, total_bytes=excluded.total_bytes,
    heap_bytes=excluded.heap_bytes, toast_bytes=excluded.toast_bytes,
    index_bytes=excluded.index_bytes, dead_tuples=excluded.dead_tuples,
    min_data_date=excluded.min_data_date, max_data_date=excluded.max_data_date,
    captured_at=now();

  for v_col in
    select column_name, ordinal_position, data_type
      from information_schema.columns
     where table_schema='public' and table_name=p_table
     order by ordinal_position
  loop
    execute format(
      'select count(%1$I),
              coalesce(sum(pg_column_size(%1$I)),0),
              count(distinct %1$I),
              avg(length(%1$I::text)),
              min(length(%1$I::text)),
              max(length(%1$I::text))
         from %2$s%3$s',
      v_col.column_name, v_reg, v_where)
    into v_nonnull, v_bytes, v_distinct, v_avg, v_min, v_max;

    insert into column_stats(
      captured_date, table_name, column_name, ordinal, data_type,
      non_null_count, null_count, distinct_count, total_bytes,
      avg_len, min_len, max_len)
    values (v_today, v_name, v_col.column_name, v_col.ordinal_position,
            v_col.data_type, v_nonnull, v_rows - v_nonnull, v_distinct,
            v_bytes, v_avg, v_min, v_max)
    on conflict (captured_date, table_name, column_name) do update set
      ordinal=excluded.ordinal, data_type=excluded.data_type,
      non_null_count=excluded.non_null_count, null_count=excluded.null_count,
      distinct_count=excluded.distinct_count, total_bytes=excluded.total_bytes,
      avg_len=excluded.avg_len, min_len=excluded.min_len, max_len=excluded.max_len,
      captured_at=now();
  end loop;
end;
$$;

revoke execute on function capture_table_stats(text, text, text, boolean, text, boolean) from public;
grant execute on function capture_table_stats(text, text, text, boolean, text, boolean) to service_role;
