-- The old zero-arg versions ran a single UPDATE over the whole table, which
-- exceeds the authenticator role's 8s statement_timeout once enough
-- non-Seattle rows accumulate (see fetch_watchlist_jobs.py RPC calls).
-- Replaced with batched versions the script calls in a loop, each batch
-- small enough to finish well under the timeout.

DROP FUNCTION IF EXISTS "public"."null_non_seattle_description"();

CREATE OR REPLACE FUNCTION "public"."null_non_seattle_description"("batch_size" integer DEFAULT 2000) RETURNS bigint
    LANGUAGE "sql"
    AS $$
  WITH batch AS (
    SELECT watchlist_company, ats_id
    FROM job_content
    WHERE seattle_and_remote = false
      AND description IS NOT NULL
    LIMIT batch_size
  ),
  updated AS (
    UPDATE job_content c
    SET description = NULL
    FROM batch b
    WHERE c.watchlist_company = b.watchlist_company
      AND c.ats_id = b.ats_id
    RETURNING 1
  )
  SELECT count(*) FROM updated;
$$;

ALTER FUNCTION "public"."null_non_seattle_description"("batch_size" integer) OWNER TO "postgres";


DROP FUNCTION IF EXISTS "public"."null_non_seattle_raw"();

CREATE OR REPLACE FUNCTION "public"."null_non_seattle_raw"("batch_size" integer DEFAULT 2000) RETURNS bigint
    LANGUAGE "sql"
    AS $$
  WITH batch AS (
    SELECT watchlist_company, ats_id
    FROM job_content
    WHERE seattle_and_remote = false
      AND raw IS NOT NULL
    LIMIT batch_size
  ),
  updated AS (
    UPDATE job_content c
    SET raw = NULL
    FROM batch b
    WHERE c.watchlist_company = b.watchlist_company
      AND c.ats_id = b.ats_id
    RETURNING 1
  )
  SELECT count(*) FROM updated;
$$;

ALTER FUNCTION "public"."null_non_seattle_raw"("batch_size" integer) OWNER TO "postgres";
