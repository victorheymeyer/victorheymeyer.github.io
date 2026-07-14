# supabase/history — archive, not migrations

These 16 `.sql` files are a **record**, not a replayable migration set. Nothing
reads them. Nothing runs them. They exist so the changes made to the
`jobs-tracker` database between 2026-07-10 and 2026-07-13 are visible in git.

## Where they came from

They were applied to the live database by Claude Code via the Supabase MCP
`apply_migration` tool, which records every call it makes in the
`supabase_migrations.schema_migrations` table. They were recovered from that
table with:

```sql
select version,
       name,
       array_to_string(statements, E'\n\n') as sql
from supabase_migrations.schema_migrations
order by version;
```

## Why they are not in supabase/migrations/

The base schema (`raw_watchlist_jobs`, `job_content`, `watchlist_companies`, the
original `jobs_location_flags` view) was created by hand in the Supabase SQL
editor and was never captured by any migration. So these 16 files start
mid-story: `add_seattle_and_remote_to_refresh_location_flags` alters a function
on tables that no file here creates.

Faithful as history. Useless as a rebuild. Replaying them against an empty
database fails immediately.

The fix was to take a **baseline**: repair the migration history table (removing
these 16 rows from the remote's bookkeeping, without touching the schema or the
data), then run `supabase db pull` to capture the complete current schema as one
migration. That baseline lives in `supabase/migrations/` and every effect of
these 16 statements is already folded into it.

## What to do with them

Read them. Don't run them. Real forward history starts at the baseline.
