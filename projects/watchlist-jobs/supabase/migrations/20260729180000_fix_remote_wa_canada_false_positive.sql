-- Xero (Workday) postings for Canada use the location code prefix "CAN:"
-- rather than the spelled-out country name, e.g.:
--   "CAN: British Columbia Remote; CAN: VAN (333 Seymour St)"
--   "CAN: British Columbia Remote"
-- refresh_location_flags()'s foreign-country exclusion list only matched
-- "canada" (and the provinces ontario/quebec/alberta, added in
-- 20260721230027/20260721223043), so "CAN:" and "British Columbia" both
-- fell through unmatched. With no country/province match to disqualify it,
-- the bare "\mremote\M" branch flagged these as maybe_remote_wa = true even
-- though nothing about the posting is WA-eligible.
--
-- Fix: add the "can" abbreviation and "british columbia" to the same
-- exclusion list already used for canada/ontario/quebec/alberta, in both
-- places it's duplicated (maybe_remote_wa and seattle_and_remote).
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
           location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|can|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|british columbia|delhi|emea)\M'
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
             location ~* '\m(ireland|germany|france|colombia|australia|mexico|india|belgium|denmark|brazil|canada|can|singapore|malaysia|philippines|chile|sweden|israel|switzerland|poland|netherlands|spain|italy|finland|china|united kingdom|england|scotland|norway|austria|portugal|japan|korea|argentina|peru|toronto|london|bangalore|amsterdam|berlin|paris|stockholm|aarhus|ontario|quebec|alberta|british columbia|delhi|emea)\M'
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
