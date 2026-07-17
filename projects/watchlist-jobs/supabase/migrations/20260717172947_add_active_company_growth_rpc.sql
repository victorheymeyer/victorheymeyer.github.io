-- RPC for the watchlist growth chart: distinct companies with at least one
-- posting per snapshot_date, as a proxy for how many watchlist companies were
-- actively producing data on a given day (there's no history table on
-- watchlist_companies.active itself, so this is derived from raw_watchlist_jobs).
CREATE OR REPLACE FUNCTION public.active_company_growth()
RETURNS TABLE(snapshot_date date, companies bigint)
LANGUAGE sql
STABLE
AS $function$
  select snapshot_date, count(distinct watchlist_company) as companies
  from raw_watchlist_jobs
  group by snapshot_date
  order by snapshot_date;
$function$;

GRANT ALL ON FUNCTION public.active_company_growth() TO anon;
GRANT ALL ON FUNCTION public.active_company_growth() TO authenticated;
