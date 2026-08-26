# victorheymeyer.github.io

- The job detail panel is defined once in /job-detail.js and styled in
  styles.css (the "Job detail panel" section). Any page showing job details
  must call JobDetail.render() rather than writing its own markup — never
  inline a copy.
- API keys and secrets live in GitHub Actions secrets only, never client-side.
  The Supabase anon key is the only key allowed in browser code.

## Local dev server

A static file server for this repo runs on `http://localhost:3000` (config in
`.claude/launch.json`, `npx serve -l 3000 .`, root = repo root). Start it via
Bash at the start of a session if it isn't already running — don't rely on it
having been left running or auto-starting. For any front-end change, give the
user the `http://localhost:3000/...` link to the changed page(s) so they can
verify in their own browser, matching the page's path under the repo root
(e.g. a change to `projects/watchlist-jobs/stats/index.html` gets
`http://localhost:3000/projects/watchlist-jobs/stats/index.html`).

## Git workflow

When the user says "commit", commit AND push in the same step — no separate
confirmation needed for the push — as long as there are no issues with the
commit (e.g. unexpected files staged, secrets in the diff, failing
pre-commit hooks). If something looks off, stop and flag it instead of
pushing.

## Verify with data, not green checkmarks

A workflow run showing green, a migration reporting success, or an editor
"saved" message is not evidence the intended change landed. Confirm with the
actual effect: row counts, a SELECT, the rendered page. "The job ran" and "the
rows are in the table" are different claims. Check the second one.

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

## Daily VACUUM FULL maintenance window (jobs-tracker, do not run manual bulk writes then)

pg_cron runs `VACUUM FULL` on `job_content` and `raw_watchlist_jobs` every day,
back-to-back, at **13:44-13:52 UTC** (~6:44-6:52am Seattle): jobs 4/7 (job_content
at 13:45/13:47) and jobs 5/8 (raw_watchlist_jobs at 13:49/13:51). `VACUUM FULL`
takes an `AccessExclusiveLock` for its duration, blocking every read against
that table — unlike plain `VACUUM`, which doesn't block readers.

Never run a manual bulk UPDATE/DELETE against `job_content` or
`raw_watchlist_jobs` inside that window (e.g. via `mcp__supabase__execute_sql`
or the dashboard SQL editor). Two things stack when you do: your statement
queues behind (or holds off) the cron's exclusive lock, and every page read
that hits the table (index.html/my-jobs.html/global.html/dev-env, all via the
`jobs_location_flags` view) queues behind that combined lock and hits the
2-minute `statement_timeout`, surfacing as "Could not load data. canceling
statement due to statement timeout" site-wide. This already happened once,
2026-08-24 ~13:45-13:51 UTC, when a manual `null_non_seattle_description`/
`null_non_seattle_raw` batch run collided with the job_content vacuum.

Run ad-hoc bulk writes on these two tables outside 13:44-13:52 UTC. The
schedule itself is intentional (fights TOAST bloat from the description/raw
nulling pattern — see migration `20260714181838_restore_vacuum_full_cron.sql`)
and should not be removed; if the collision risk needs fixing, that's a
change to make deliberately (e.g. widen the reserved window, or move to a
non-exclusive-lock reclaim method), not a side effect of a maintenance script.

## One scraper cron per database (jobs-tracker)

Only one repo may run the scraper cron against the jobs-tracker Supabase
instance at a time. Two crons writing the same tables on the same schedule
double-write every snapshot. This matters most during a repo move: when setting
up the scraper workflow in a new repo, leave its cron disabled until the old
repo's cron is confirmed off. Verify the old cron is actually disabled, not just
assumed, before arming the new one.

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