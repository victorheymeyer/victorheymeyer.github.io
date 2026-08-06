# victorheymeyer.github.io

- The job detail panel is defined once in /job-detail.js and styled in
  styles.css (the "Job detail panel" section). Any page showing job details
  must call JobDetail.render() rather than writing its own markup — never
  inline a copy.
- API keys and secrets live in GitHub Actions secrets only, never client-side.
  The Supabase anon key is the only key allowed in browser code.

## Timezone invariant (jobs-tracker only)

Two storage types, two rules. Never collapse them.

- `timestamptz` columns are ALWAYS UTC. Never convert to naive or local time.
  Storage and `now()` defaults stay as-is. (posted_at, fetched_at, created_at,
  updated_at, added_at.)
- Plain `date` columns are ALWAYS a Seattle calendar day, defined as
  `(now() at time zone 'America/Los_Angeles')::date`. (snapshot_date,
  first_seen, last_seen, current_version_first_seen.)

Core invariant: every `date` value in the system, in any table, must be born
from the Seattle wall clock, never from UTC. A `date` derived via
`(now() at time zone 'utc')::date` is a bug even when it happens to match today.

In Python, reuse the existing `SEATTLE_TZ` constant in fetch_watchlist_jobs.py.
Do not redefine it.

Cron limitation (known, accepted, do NOT try to fix): GitHub Actions cron and
pg_cron are UTC/GMT-only with no per-job Seattle setting. Trigger times can
never be Seattle-local and will drift ~1hr at DST. This is permanent. Gate on
the Seattle day inside the job if a specific day boundary matters; never treat
the cron trigger time as authoritative.
