-- Patch refresh_location_flags() for Workday-format false positives.
--
-- Verified against a fixture set of real Workday/Greenhouse/Ashby/Lever location
-- strings (see handoff) before and after this change; every previously-correct
-- case still passes. Fixes, without altering already-correct behavior:
--
--   1. Directional blind spot: "Georgia - Atlanta Metro - Remote" (state before
--      "remote") was not excluded — only "Remote - CA" (state after) was. The
--      remote-exclusion state check is now unanchored (matches the state token
--      anywhere in the string) instead of requiring adjacency to "remote"/"us-".
--      This also incidentally fixes parenthetical forms like "Remote (TX)".
--   2. "USA DC Washington" (DC token before "Washington") leaked through as WA
--      state; the old DC exclusion only matched the "Washington ... DC" order.
--   3. Bare "Washington" collided with "Fort Washington, MD" / "Port Washington, NY".
--   4. Bare "WA" also matched Western Australia (e.g. "AU-WA-EXMOUTH-HEH-CUST").
--
-- Bugs 2 and 3 share one fix: the bare WA/washington match now requires that no
-- *other* US state or DC token appears anywhere in the string. Bug 4 reuses the
-- existing non-US country-code-prefix guard already present in maybe_remote_wa.
--
-- Explicitly NOT fixed here (needs the segment-splitting rewrite, not a regex
-- patch): a remote posting restricted to a non-US country via a bare code with
-- no recognizable country name, e.g. "Remote (BRA)".
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
        )
      )
  WHERE location IS NOT NULL;
$function$;
