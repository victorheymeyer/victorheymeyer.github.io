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

## ats-scrapers fork (contribution scratch, not production)

The `ats-scrapers` clone at `C:\Users\vheym\ats-scrapers` is throwaway scratch for an upstream PR (Workday startDate/endDate), NOT a source for this pipeline. The production scraper is the vendored wheel at `projects/watchlist-jobs/vendor/ats_scrapers-0.2.0-py3-none-any.whl`; never vendor or install from that clone.

## Supabase migration history drift (jobs-tracker, resolved 2026-08-22)

`supabase db push --linked` previously failed with "Remote migration versions
not found in local migrations directory" for ~40 migrations dated 2026-07-24
through 2026-08-22. Root cause: the remote `supabase_migrations.schema_migrations`
table recorded a different timestamp than the local filename for the same
migration (same name, different stamp) — likely from migrations applied via
direct SQL/API rather than `db push`. Fixed via `supabase migration repair`
(remote-only timestamps → `reverted`, matching local timestamps → `applied`;
this only edits the bookkeeping table, never touches actual schema/data).

If this recurs: don't just apply the CLI's suggested repair blindly. Diff
`mcp__supabase__list_migrations` against local filenames by migration *name*
(ignoring timestamp) first — most mismatches are same migration/different
stamp (safe to repair straight across), but check for:
- remote-only entries with no local counterpart at all (abandoned/squashed
  migrations — just mark reverted, nothing to reapply)
- local-only pending migrations — read the file before pushing; one
  (`20260729180000_fix_remote_wa_canada_false_positive.sql`) was fully
  superseded by a later already-applied migration (`rewrite_remote_wa_as_inclusion_based`)
  and would have regressed `refresh_location_flags()` to older logic if pushed.
  Mark superseded-but-never-run migrations `applied` (skip) rather than running them.

For a one-off schema change when `db push` is blocked, `mcp__supabase__apply_migration`
applies DDL directly and records its own (new) history entry — but that new
entry will itself drift from the local file's timestamp, so still needs the
same repair treatment before the next `db push`.