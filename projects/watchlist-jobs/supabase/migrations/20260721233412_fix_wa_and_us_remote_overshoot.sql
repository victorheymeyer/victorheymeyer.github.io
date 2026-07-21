-- Fix two "went too far" regressions introduced by the prior two location-flag
-- patches (20260721223043, 20260721230027).
--
-- Both prior patches generalized "is another state/country present?" to check
-- the WHOLE location string rather than requiring adjacency to "remote". That
-- correctly closed several false-positive leaks, but it also can't distinguish
-- "restricted to state X" from "eligible in state X among several others,
-- including WA/nationwide" when a posting lists multiple alternatives in one
-- string. Two concrete regressions found in production data:
--
--   1. WA explicitly listed as one of several eligible remote states got
--      cancelled out by the OTHER states also being listed, e.g.:
--        Databricks: "Colorado; Remote - California; Remote - Oregon; Remote - Washington"
--        Salesforce: "California - Remote | ... | Washington - Remote | ..."
--      27 real rows affected.
--
--   2. A location listing specific office cities as alternatives to a plain
--      nationwide "US-Remote"/"Remote - US"/"US, Remote" option got excluded
--      because of the specific cities, even though the US-Remote alternative
--      alone should make it WA-eligible, e.g.:
--        Airtable: "Austin, TX; Remote - US"
--        Salesforce: "Illinois - Chicago | US, Remote"
--      14 real rows affected.
--
-- Fix: add two affirmative short-circuit overrides ahead of the general
-- exclusion logic, so they win regardless of what else is in the string:
--   (a) "remote" tightly hyphen-paired with "WA"/"washington" anywhere.
--   (b) any semicolon/pipe-separated segment that reduces to *exactly*
--       "US" + "Remote" (optionally "US-based Remote"), nothing else attached.
--
-- (b) is intentionally narrow — it only splits on ; and | (not comma), so
-- "US, Remote" (comma used as the internal connector, e.g. Salesforce) is
-- preserved as one segment. This was verified NOT to wrongly flip:
--   "US-REMOTE-Florida"        (Instructure — actually Florida-specific)
--   "US Remote- ET or CT Time Zone" (15five — ET/CT-restricted, excludes
--                                     Pacific-time WA, correctly excluded)
--   "US-VA-Remote"             (Snowflake — actually Virginia-specific)
-- because in all three, "remote" isn't immediately followed only by a
-- segment boundary — something else (a state name or timezone qualifier) is
-- still attached within the same segment.
--
-- Known accepted residual gap: a handful of Stripe postings use *comma* as
-- the only separator between city alternatives and a trailing "US-Remote"
-- (e.g. "New York, San Francisco, US-Remote", "SF, NY, SEA, Remote-US").
-- Splitting on comma too would catch these, but it would also break the
-- Salesforce "US, Remote" case above (same character, opposite meaning in
-- each ATS's format) — not worth that trade for ~5 known rows.
CREATE OR REPLACE FUNCTION public.refresh_location_flags()
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE job_content SET
    maybe_wa =
      (
        (
          location ~* '\m(WA|washington)\M'
          AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
          AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'
        )
        OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
      ),
    maybe_remote_wa =
      (
        location ~* '(\mremote\M\s*[-–]\s*\m(wa|washington)\M)|(\m(wa|washington)\M\s*[-–]\s*\mremote\M)'
        OR EXISTS (
          SELECT 1 FROM regexp_split_to_table(location, '\s*[;|]\s*') AS seg
          WHERE seg ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*[-,]?\s*(based\s*)?remote\s*$'
             OR seg ~* '^\s*remote\s*[-,]?\s*(based\s*)?(the\s+)?u\.?s\.?a?\.?\s*$'
        )
        OR
        (location ~* '\m(remote|anywhere)\M'
         AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
         AND NOT (
           location ~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M'
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
           AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
         )
         AND NOT (
           (location ~* 'washington[,.\s]*d\.?\s*c\.?' OR location ~* '\mdc\M')
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
           AND NOT (location ~* '\m(usa|united states|north america|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|sf|nyc|ny|sea|chi)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
         )
         AND NOT (
           location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|delhi|emea)\M'
           AND location !~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane|washington|wa|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|us|usa|united states|north america|sf|nyc|ny|sea|chi|dc)\M'
         )
         AND NOT (
           location ~* 'remote\s*[-–,/(]\s*[a-z]{2,}'
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
           AND NOT (location ~* '\m(us|usa|united states|north america|any|nationwide|national|global|worldwide|anywhere|flexible)\M')
         )
        )
      ),
    seattle_and_remote =
      (
        (
          (
            location ~* '\m(WA|washington)\M'
            AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
            AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'
          )
          OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
        )
        OR
        (
          location ~* '(\mremote\M\s*[-–]\s*\m(wa|washington)\M)|(\m(wa|washington)\M\s*[-–]\s*\mremote\M)'
          OR EXISTS (
            SELECT 1 FROM regexp_split_to_table(location, '\s*[;|]\s*') AS seg
            WHERE seg ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*[-,]?\s*(based\s*)?remote\s*$'
               OR seg ~* '^\s*remote\s*[-,]?\s*(based\s*)?(the\s+)?u\.?s\.?a?\.?\s*$'
          )
          OR
          (location ~* '\m(remote|anywhere)\M'
           AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
           AND NOT (
             location ~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|dc|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M'
             AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
             AND NOT (location ~* '\m(usa|united states|north america)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
           )
           AND NOT (
             (location ~* 'washington[,.\s]*d\.?\s*c\.?' OR location ~* '\mdc\M')
             AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
             AND NOT (location ~* '\m(usa|united states|north america|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|sf|nyc|ny|sea|chi)\M' OR location ~* 'the\s+u\.?\s*s\.?\M')
           )
           AND NOT (
             location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|delhi|emea)\M'
             AND location !~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane|washington|wa|san francisco|new york|chicago|atlanta|boston|sunnyvale|livingston|denver|austin|los angeles|us|usa|united states|north america|sf|nyc|ny|sea|chi|dc)\M'
           )
           AND NOT (
             location ~* 'remote\s*[-–,/(]\s*[a-z]{2,}'
             AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
             AND NOT (location ~* '\m(us|usa|united states|north america|any|nationwide|national|global|worldwide|anywhere|flexible)\M')
           )
          )
        )
      )
  WHERE location IS NOT NULL;
$function$;
