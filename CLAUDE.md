# victorheymeyer.github.io

- API keys and secrets live in GitHub Actions secrets only, never client-side.
  The Supabase anon key is the only key allowed in browser code.
- Only one repo may run a scheduled writer (cron workflow) against a given
  Supabase database at a time; two crons double-write. Before arming a cron in
  a new repo, verify the old one is actually disabled.
- GitHub Actions cron is UTC-only and drifts ~1hr at DST. Never treat the
  trigger time as Seattle-local; gate on the Seattle day inside the job if a
  day boundary matters.

## Local dev server

A static file server for this repo runs on `http://localhost:3000` (config in
`.claude/launch.json`, `npx serve -l 3000 .`, root = repo root). Start it via
Bash at the start of a session if it isn't already running — don't rely on it
having been left running or auto-starting. For any front-end change, give the
user the `http://localhost:3000/...` link to the changed page(s) so they can
verify in their own browser, matching the page's path under the repo root
(e.g. a change to `projects/llm-data/index.html` gets
`http://localhost:3000/projects/llm-data/index.html`).

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
