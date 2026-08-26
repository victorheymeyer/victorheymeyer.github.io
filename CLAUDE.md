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

Never use the internal Browser pane / preview tools (`mcp__Claude_Browser__*`)
for this repo, even briefly to self-verify a UI change before reporting done.
Start the server, hand the user the localhost link, and let them check it in
their own system browser. Only use the internal Browser pane if the user
explicitly asks for it.

## Git workflow

Once a change is ready, proactively surface that it's ready ("want me to
commit this?") — don't wait to be asked, and don't assume silence means
go-ahead for the first commit.

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

## ats-scrapers naming history and which install to use (jobs-tracker)

The scraper package was renamed once: it used to be called `jobhive-py`
(0.1.0) and its response shape changed across that rename — see the comment
at fetch_watchlist_jobs.py:89. The current name is `ats-scrapers` (import
name `ats_scrapers`), upstream at https://github.com/kalil0321/ats-scrapers,
currently 0.2.0. `jobhive-py` is dead history, not an alternate name to
install or import — if a command, doc, or old reference mentions it, treat
it as referring to today's `ats-scrapers`.

Two different copies of `ats_scrapers` can exist on this machine and it
matters which one is active:

- **Production source**: the vendored wheel at
  `projects/watchlist-jobs/vendor/ats_scrapers-0.2.0-py3-none-any.whl`. This
  is what the pipeline (fetch_watchlist_jobs.py, probe_ats.py) must run
  against.
- **Contribution scratch**: an editable clone at `C:\Users\vheym\ats-scrapers`
  used only for drafting an upstream PR (Workday startDate/endDate). Not a
  source for this pipeline, even if `pip show ats-scrapers` reports the same
  version number — an editable install can diverge from the wheel without
  the version bumping. Never vendor or install from that clone.

If `pip show ats-scrapers` points at an `Editable project location` under
`C:\Users\vheym\ats-scrapers` in an environment meant to run this pipeline,
that's the scratch fork shadowing the vendored wheel — reinstall from the
wheel before trusting pipeline output.

## Probe pipeline invariants (jobs-tracker)

The company-discovery probe pipeline (`ats_probe_results`, `probe_decisions`,
`ats_probe_latest` view, `next_probe_batch()`, `probe_ats.py`, daily
`probe-ats.yml` cron) has several non-obvious decisions that are easy to
accidentally regress:

- **Legacy discriminator is `probed_at < '2026-07-22'`, not `status IS NULL`.**
  Pre-2026-07-22 rows already have a populated `status` in an old vocabulary
  that collides with the current `'ok'|'empty'|'gone'|'error'` set.
- **CA/Canada handling is intentionally asymmetric.** Onsite `bay_jobs`
  accepts bare "CA" only in strict postal context. Remote `remote_ca_jobs`
  never accepts bare "CA" (too likely to mean Canada) — requires full
  "California" or a known city. Don't loosen remote to match onsite.
- **DC exclusion only applies to WA's onsite/remote branches** (word
  collision with "Washington, D.C."). Don't add it to NY/CA branches.
- **`probe_ats.py` writes one result immediately per company, never
  batches.** This is the crash-resumption contract — a killed run leaves
  correct rows for everything already done.
- **Eightfold `status='error'` rows under Cloudflare block are expected,
  not a bug** (e.g. Citi, Deloitte) — the `httpcloak` bypass is an optional
  wheel extra, not installed in this project.
- **Workday rows in `watchlist_companies` use a different shape than every
  other ATS**: `company` (the PK) is the directory's `tenant/site` slug with
  `/` → `__` (e.g. `remitly__remitly_careers`), not the human display name;
  `slug` is the full careers URL, not a short slug. Every other ATS uses the
  human name for `company` and the short slug verbatim. Get this backwards
  and promotion collides or writes garbage company names.
- **`watchlist_companies.display_name` has no default and nothing
  coalesces it.** Any manual or scripted insert must set it explicitly, or
  the UI falls back to the raw `company` value (ugly for Workday).
- **Auto-approve (`auto_approve_probe_decisions()`) and auto-promote
  (`promote_probe_decisions()`) are wired into `probe_ats.py`'s `main()`
  but commented out / ON HOLD as of 2026-08-25 at Victor's request.** Don't
  re-enable without being explicitly asked, even if it looks safe to resume.

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