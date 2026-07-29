-- refresh_location_flags()'s maybe_remote_wa/seattle_and_remote logic was
-- exclusion-based: assume WA-eligible whenever "remote" appears, unless the
-- location matches a hardcoded blocklist of non-US countries/cities. That
-- blocklist can never be complete -- Xero postings alone surfaced CAN/UK/NZ/AU
-- location-code prefixes, plus spelled-out Taiwan, Romania, UAE, Saudi Arabia,
-- Uruguay, South Africa, Costa Rica, Ukraine, Thailand, Oman, Bulgaria,
-- Panama, Indonesia, Hong Kong, and city names (Madrid, Dublin, Milan,
-- Montreal/Vancouver/Calgary, several German cities) that were never in the
-- list at all, plus spelling/accent variants (Brasil vs brazil, Quebec vs
-- Quebec) of countries that were.
--
-- This replaces it with inclusion-based logic: maybe_remote_wa is true only
-- when the location contains "remote"/"anywhere" AND an explicit WA/US/
-- nationwide signal, OR the location is bare "remote"/"anywhere" with no
-- other geographic text at all (kept permissive for that one specific case
-- -- ambiguous, but no evidence either way, so left as-is rather than
-- flipped to false). Verified against production job_content data: of 3,119
-- rows currently true, 167 flip to false (foreign locations previously
-- missed by the blocklist, e.g. "CAN: British Columbia Remote", "UK -
-- Remote", "Taiwan - Remote" -- plus a bonus fix, several "Remote -
-- Washington D.C." rows that were true only because the old function's
-- hyphen-adjacent WA-remote shortcut bypassed its own DC-vs-WA-state
-- disambiguation used everywhere else) and 93 flip from false to true
-- (multi-state remote lists including WA, e.g. "Remote - California; ...;
-- Remote - Washington", that the old logic's stricter "no other state
-- present" guard was wrongly excluding, plus "Remote (US)"-style
-- parenthesized forms the old segment-exact check couldn't parse).
--
-- Known, accepted trade-off: US cities without an explicit "US"/"United
-- States" token (e.g. "Boston - Remote", "San Francisco; Remote") now read
-- as false rather than true. No city allowlist is added for these --
-- explicit choice, since a missed true is a minor omission but a
-- false positive (a Dubai or Taiwan posting showing up as WA-eligible)
-- actively pollutes the filtered view.
--
-- maybe_wa (WA presence, not remote-specific) is unchanged.
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
        location ~* '\m(remote|anywhere)\M'
        AND (
          (
            location ~* '\m(wa|washington)\M'
            AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
            AND location !~* '\mdc\M|d\.c\.?|district of columbia'
          )
          OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
          OR location ~* '\m(usa|united states|north america)\M'
          OR location ~* '\m(nationwide|national|global|worldwide|flexible)\M'
          OR EXISTS (
            SELECT 1 FROM regexp_split_to_table(location, '\s*[;|,]\s*') AS seg
            WHERE regexp_replace(seg, '[()]', '', 'g') ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*[-,]?\s*(based\s*)?remote\s*$'
               OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*remote\s*[-,]?\s*(based\s*)?(the\s+)?u\.?s\.?a?\.?\s*$'
               OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*$'
               OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*remote\s+in\s+the\s+u\.?s\.?a?\.?\s*$'
          )
          OR location ~* '^\s*(remote|anywhere)(\s*[;|,]\s*(remote|anywhere))*\s*$'
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
          location ~* '\m(remote|anywhere)\M'
          AND (
            (
              location ~* '\m(wa|washington)\M'
              AND NOT (location ~ '^[A-Z]{2}-' AND location !~* '^US-')
              AND location !~* '\mdc\M|d\.c\.?|district of columbia'
            )
            OR location ~* '\m(seattle|bellevue|redmond|kirkland|bothell|woodinville|renton|kent|issaquah|sammamish|mercer island|tukwila|lynnwood|everett|bremerton|tacoma|spokane)\M'
            OR location ~* '\m(usa|united states|north america)\M'
            OR location ~* '\m(nationwide|national|global|worldwide|flexible)\M'
            OR EXISTS (
              SELECT 1 FROM regexp_split_to_table(location, '\s*[;|,]\s*') AS seg
              WHERE regexp_replace(seg, '[()]', '', 'g') ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*[-,]?\s*(based\s*)?remote\s*$'
                 OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*remote\s*[-,]?\s*(based\s*)?(the\s+)?u\.?s\.?a?\.?\s*$'
                 OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*(the\s+)?u\.?s\.?a?\.?\s*$'
                 OR regexp_replace(seg, '[()]', '', 'g') ~* '^\s*remote\s+in\s+the\s+u\.?s\.?a?\.?\s*$'
            )
            OR location ~* '^\s*(remote|anywhere)(\s*[;|,]\s*(remote|anywhere))*\s*$'
          )
        )
      )
  WHERE location IS NOT NULL;
$function$;
