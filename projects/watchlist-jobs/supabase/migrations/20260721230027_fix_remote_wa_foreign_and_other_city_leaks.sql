-- Close the "Remote (BRA)" / "Remote-Dublin" / "Remote-Taipei" / "Remote-Shenzhen"
-- gap in maybe_remote_wa (and its mirror in seattle_and_remote).
--
-- The prior fix (20260721223043) closed directional/DC/other-US-state gaps but
-- left foreign locations covered only by an enumerated country/city list
-- (ireland, china, london, paris, ... — a handful of major cities). Any foreign
-- city not on that list, or a bare 3-letter country code like "BRA"/"SAU" in a
-- "Remote (XXX)" annotation, still leaked through as TRUE. Enumerating every
-- world city is a losing battle, so instead of extending that list further we
-- add one general rule: if "remote" is tightly attached to some token via
-- -, (, , or / (e.g. "Remote-Dublin", "Remote (BRA)", "Remote, Tokyo"), and
-- that token is neither a recognized WA signal nor a generic "unrestricted"
-- qualifier (US, USA, Any, Nationwide, Global, Worldwide, Anywhere, Flexible),
-- treat it as restricted elsewhere. This is a conservative-default shift
-- scoped narrowly to this one "remote-directly-attached-to-something" pattern,
-- not applied to bare "Remote" with no attached qualifier.
--
-- Verified against the full existing fixture set (no regressions) plus:
--   Remote (BRA)      -> now FALSE (was TRUE)
--   Remote-Dublin      -> now FALSE (was TRUE)
--   Remote-Taipei       -> now FALSE (was TRUE)
--   Remote-Shenzhen      -> now FALSE (was TRUE)
--   Remote-Seattle (control) -> still TRUE
--   Remote - Austin (bonus)  -> now FALSE (non-WA US city, same gap class)
--   Remote - Nationwide (control) -> still TRUE
--
-- Known accepted tradeoff: a genuine WA-remote posting phrased as
-- "Remote-<city>" for a WA city NOT in the hardcoded list below (seattle,
-- bellevue, redmond, kirkland, bothell, woodinville, renton, kent, issaquah,
-- sammamish, mercer island, tukwila, lynnwood, everett, bremerton, tacoma,
-- spokane) will now incorrectly return FALSE instead of leaking through as
-- TRUE. Accepted deliberately — extend the WA city list if/when this shows up
-- in real data.
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
       AND NOT (
         location ~* 'remote\s*[-–,/(]\s*[a-z]{2,}'
         AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
         AND NOT (location ~* '\m(us|usa|united states|north america|any|nationwide|national|global|worldwide|anywhere|flexible)\M')
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
         AND NOT (
           location ~* 'remote\s*[-–,/(]\s*[a-z]{2,}'
           AND NOT (location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M' OR (location ~* '\m(wa|washington)\M' AND location !~* '\m(al|ak|az|ar|ca|co|ct|de|fl|ga|hi|id|il|in|ia|ks|ky|la|me|md|ma|mi|mn|ms|mo|mt|ne|nv|nh|nj|nm|ny|nc|nd|oh|ok|or|pa|ri|sc|sd|tn|tx|ut|vt|va|wv|wi|wy|alabama|alaska|arizona|arkansas|california|colorado|connecticut|delaware|florida|georgia|hawaii|idaho|illinois|indiana|iowa|kansas|kentucky|louisiana|maine|maryland|massachusetts|michigan|minnesota|mississippi|missouri|montana|nebraska|nevada|new hampshire|new jersey|new mexico|new york|north carolina|north dakota|ohio|oklahoma|oregon|pennsylvania|rhode island|south carolina|south dakota|tennessee|texas|utah|vermont|west virginia|virginia|wisconsin|wyoming)\M|\mdc\M|d\.c\.?|district of columbia'))
           AND NOT (location ~* '\m(us|usa|united states|north america|any|nationwide|national|global|worldwide|anywhere|flexible)\M')
         )
        )
      )
  WHERE location IS NOT NULL;
$function$;
