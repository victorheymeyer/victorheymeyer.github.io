


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."ats_company_directory_counts"() RETURNS TABLE("ats" "text", "companies" bigint)
    LANGUAGE "sql" STABLE
    AS $$
  select ats, count(*) as companies
  from ats_company_directory
  group by ats
  order by ats;
$$;


ALTER FUNCTION "public"."ats_company_directory_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."null_non_seattle_description"() RETURNS "void"
    LANGUAGE "sql"
    AS $$
  UPDATE job_content
  SET description = NULL
  WHERE seattle_and_remote = false
    AND description IS NOT NULL;
$$;


ALTER FUNCTION "public"."null_non_seattle_description"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."null_non_seattle_raw"() RETURNS "void"
    LANGUAGE "sql"
    AS $$
  UPDATE job_content
  SET raw = NULL
  WHERE seattle_and_remote = false
    AND raw IS NOT NULL;
$$;


ALTER FUNCTION "public"."null_non_seattle_raw"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_job_freshness"("run_date" "date") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
begin
    -- Set first_seen only where missing (set-once; never overwrites existing)
    update job_content
    set first_seen = run_date
    where first_seen is null;

    -- New version detected: stored hash differs from the just-written current hash.
    -- We compare job_content's current_description_hash (from last run) against
    -- the latest hash now in the fact table for run_date.
    update job_content c
    set current_version_first_seen = run_date,
        current_description_hash = f.description_hash
    from (
        select watchlist_company, ats_id, description_hash
        from raw_watchlist_jobs
        where snapshot_date = run_date
    ) f
    where c.watchlist_company = f.watchlist_company
      and c.ats_id = f.ats_id
      and f.description_hash is not null
      and c.current_description_hash is distinct from f.description_hash;
end;
$$;


ALTER FUNCTION "public"."refresh_job_freshness"("run_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."refresh_location_flags"() RETURNS "void"
    LANGUAGE "sql"
    AS $$
  UPDATE job_content SET
    maybe_wa =
      (location ~* '\m(WA|washington)\M'
         AND location !~* 'washington,?\s*d\.?c\.?'
       OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
      ),
    maybe_remote_wa =
      (location ~* '\m(remote|anywhere)\M'
       AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
       AND NOT (
         location ~* 'remote\s*[-,/]*\s*\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M'
         AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
         AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
       )
       AND NOT (
         location ~* '\mus[-\s]+\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc)\M'
         AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
         AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
       )
       AND NOT (
         (location ~* 'washington[,.\s]*d\.?\s*c\.?' OR location ~* '\mdc\M')
         AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
         AND NOT (location ~* '\m(usa|united states|north america|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|sf|nyc|ny|sea|chi)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
       )
       AND NOT (
         location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|delhi|emea)\M'
         AND location !~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane|washington|wa|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|us|usa|united states|north america|sf|nyc|ny|sea|chi|dc)\M'
       )
      ),
    seattle_and_remote =
      (
        (location ~* '\m(WA|washington)\M'
           AND location !~* 'washington,?\s*d\.?c\.?'
         OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
        )
        OR
        (location ~* '\m(remote|anywhere)\M'
         AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
         AND NOT (
           location ~* 'remote\s*[-,/]*\s*\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M'
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
           AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
         )
         AND NOT (
           location ~* '\mus[-\s]+\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc)\M'
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
           AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
         )
         AND NOT (
           (location ~* 'washington[,.\s]*d\.?\s*c\.?' OR location ~* '\mdc\M')
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* 'washington[,.\s]*d\.?\s*c\.?'))
           AND NOT (location ~* '\m(usa|united states|north america|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|sf|nyc|ny|sea|chi)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
         )
         AND NOT (
           location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|delhi|emea)\M'
           AND location !~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane|washington|wa|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|us|usa|united states|north america|sf|nyc|ny|sea|chi|dc)\M'
         )
        )
      )
  WHERE location IS NOT NULL;
$$;


ALTER FUNCTION "public"."refresh_location_flags"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."ats_company_directory" (
    "id" bigint NOT NULL,
    "company" "text" NOT NULL,
    "ats" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "url" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."ats_company_directory" OWNER TO "postgres";


ALTER TABLE "public"."ats_company_directory" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "public"."ats_company_directory_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."job_content" (
    "watchlist_company" "text" NOT NULL,
    "ats_id" "text" NOT NULL,
    "title" "text",
    "location" "text",
    "department" "text",
    "description" "text",
    "url" "text",
    "apply_url" "text",
    "last_seen" "date",
    "fetched_at" timestamp with time zone,
    "first_seen" "date",
    "current_version_first_seen" "date",
    "current_description_hash" "text",
    "discipline" "text",
    "role_keyword" "text",
    "level" "text",
    "maybe_wa" boolean,
    "maybe_remote_wa" boolean,
    "seattle_and_remote" boolean,
    "raw" "jsonb"
);


ALTER TABLE "public"."job_content" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."raw_watchlist_jobs" (
    "snapshot_date" "date" NOT NULL,
    "watchlist_company" "text" NOT NULL,
    "ats_id" "text" NOT NULL,
    "ats_type" "text",
    "title" "text",
    "location" "text",
    "is_remote" boolean,
    "department" "text",
    "team" "text",
    "employment_type" "text",
    "salary_min" numeric,
    "salary_max" numeric,
    "salary_currency" "text",
    "posted_at" timestamp with time zone,
    "fetched_at" timestamp with time zone,
    "url" "text",
    "apply_url" "text",
    "description_hash" "text"
);


ALTER TABLE "public"."raw_watchlist_jobs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."target_filter_rules" (
    "category" "text" NOT NULL,
    "value" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "target_filter_rules_category_check" CHECK (("category" = ANY (ARRAY['discipline'::"text", 'role'::"text", 'level'::"text"])))
);


ALTER TABLE "public"."target_filter_rules" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."watchlist_companies" (
    "company" "text" NOT NULL,
    "ats" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text",
    "priority" integer DEFAULT 100 NOT NULL,
    "display_name" "text",
    "scraper_kwargs" "jsonb"
);


ALTER TABLE "public"."watchlist_companies" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."jobs_location_flags" AS
 SELECT "f"."snapshot_date",
    "f"."watchlist_company",
    "f"."ats_id",
    "f"."ats_type",
    "f"."title",
    "f"."location",
    "f"."is_remote",
    "f"."department",
    "f"."team",
    "f"."employment_type",
    "f"."salary_min",
    "f"."salary_max",
    "f"."salary_currency",
    "f"."posted_at",
    "f"."fetched_at",
    "f"."url",
    "f"."apply_url",
    "jc"."raw",
    "f"."description_hash",
    "jc"."maybe_wa",
    "jc"."maybe_remote_wa",
    "jc"."discipline",
    "jc"."role_keyword",
    "jc"."level",
    "wc"."display_name",
    ((EXISTS ( SELECT 1
           FROM "public"."target_filter_rules" "r"
          WHERE (("r"."category" = 'discipline'::"text") AND ("r"."value" = "jc"."discipline")))) AND (EXISTS ( SELECT 1
           FROM "public"."target_filter_rules" "r"
          WHERE (("r"."category" = 'role'::"text") AND ("r"."value" = COALESCE("jc"."role_keyword", '__unclassified__'::"text"))))) AND (EXISTS ( SELECT 1
           FROM "public"."target_filter_rules" "r"
          WHERE (("r"."category" = 'level'::"text") AND ("r"."value" = "jc"."level"))))) AS "is_target_match",
    "jc"."first_seen"
   FROM (("public"."raw_watchlist_jobs" "f"
     LEFT JOIN "public"."job_content" "jc" ON ((("jc"."watchlist_company" = "f"."watchlist_company") AND ("jc"."ats_id" = "f"."ats_id"))))
     LEFT JOIN "public"."watchlist_companies" "wc" ON (("wc"."company" = "f"."watchlist_company")));


ALTER VIEW "public"."jobs_location_flags" OWNER TO "postgres";


ALTER TABLE ONLY "public"."ats_company_directory"
    ADD CONSTRAINT "ats_company_directory_ats_slug_key" UNIQUE ("ats", "slug");



ALTER TABLE ONLY "public"."ats_company_directory"
    ADD CONSTRAINT "ats_company_directory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."job_content"
    ADD CONSTRAINT "job_content_pkey" PRIMARY KEY ("watchlist_company", "ats_id");



ALTER TABLE ONLY "public"."raw_watchlist_jobs"
    ADD CONSTRAINT "raw_watchlist_jobs_pkey" PRIMARY KEY ("snapshot_date", "watchlist_company", "ats_id");



ALTER TABLE ONLY "public"."target_filter_rules"
    ADD CONSTRAINT "target_filter_rules_pkey" PRIMARY KEY ("category", "value");



ALTER TABLE ONLY "public"."watchlist_companies"
    ADD CONSTRAINT "watchlist_companies_pkey" PRIMARY KEY ("company");



CREATE INDEX "idx_ats_company_directory_company_trgm" ON "public"."ats_company_directory" USING "gin" ("company" "public"."gin_trgm_ops");



CREATE INDEX "idx_raw_watchlist_jobs_snapshot_date" ON "public"."raw_watchlist_jobs" USING "btree" ("snapshot_date");



CREATE POLICY "Public read access" ON "public"."ats_company_directory" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "Public read access" ON "public"."watchlist_companies" FOR SELECT TO "authenticated", "anon" USING (true);



ALTER TABLE "public"."ats_company_directory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."job_content" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "public read job_content" ON "public"."job_content" FOR SELECT TO "anon" USING (true);



CREATE POLICY "public read raw_watchlist_jobs" ON "public"."raw_watchlist_jobs" FOR SELECT TO "anon" USING (true);



CREATE POLICY "public read target_filter_rules" ON "public"."target_filter_rules" FOR SELECT TO "anon" USING (true);



ALTER TABLE "public"."raw_watchlist_jobs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."target_filter_rules" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."watchlist_companies" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";





GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "service_role";











































































































































































GRANT ALL ON FUNCTION "public"."ats_company_directory_counts"() TO "anon";
GRANT ALL ON FUNCTION "public"."ats_company_directory_counts"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "postgres";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "anon";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "service_role";



GRANT ALL ON FUNCTION "public"."show_limit"() TO "postgres";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "service_role";
























GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ats_company_directory" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."ats_company_directory" TO "authenticated";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."ats_company_directory" TO "service_role";



GRANT SELECT,USAGE ON SEQUENCE "public"."ats_company_directory_id_seq" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."job_content" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."job_content" TO "authenticated";
GRANT ALL ON TABLE "public"."job_content" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."raw_watchlist_jobs" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."raw_watchlist_jobs" TO "authenticated";
GRANT ALL ON TABLE "public"."raw_watchlist_jobs" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."target_filter_rules" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."target_filter_rules" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."target_filter_rules" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."watchlist_companies" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."watchlist_companies" TO "authenticated";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."watchlist_companies" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."jobs_location_flags" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."jobs_location_flags" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."jobs_location_flags" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";



































