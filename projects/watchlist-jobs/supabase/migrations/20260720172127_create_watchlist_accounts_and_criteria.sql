-- Watchlist Jobs: accounts + saved criteria
-- Step 1 of 4. Creates two tables. Touches nothing existing.
--
-- Model:
--   profiles      = one row per account (identity, email, plan)
--   user_criteria = a saved, named set of filters belonging to an account
--
-- A person logs in, sets filters on the site, saves them, and sees them again
-- on their next visit. If they turn on email_daily, the digest job includes
-- them. Victor is user 1 and is an ordinary row in both tables: no filters or
-- addresses live in application code.

-- ---------------------------------------------------------------------------
-- 1. profiles: one row per auth user, created automatically on signup.
--
--    plan            -> free/paid, for a later paid tier. Nothing reads it yet.
--    newsletter_optin -> for a possible future broadcast. Nothing reads it yet.
--    Both are here because adding a column to a populated table with live RLS
--    is more disruptive than defining it empty today.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  email            text,
  plan             text not null default 'free',
  newsletter_optin boolean not null default false,
  created_at       timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
  for select using ( (select auth.uid()) = id );

create policy profiles_update_own on public.profiles
  for update using ( (select auth.uid()) = id )
  with check ( (select auth.uid()) = id );

-- No insert policy on purpose: rows are created by the trigger below, which
-- runs as definer. Clients never insert profiles directly.

-- ---------------------------------------------------------------------------
-- 2. Auto-create a profile whenever an auth user is created. Without this,
--    every new account silently lacks a profile row.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 3. user_criteria: saved filter sets. This is what makes criteria persist
--    between visits, and it is also what the digest job reads.
--
--    Shape decisions:
--
--    a) surrogate id + user_id, not user_id alone as the key. Allows several
--       named sets per person. The site can offer only one at first; adding
--       more later would otherwise mean changing the primary key.
--    b) filters JSONB. Adding a new criterion is a key in a blob, not a
--       column on a populated table. Matches the DB-as-source-of-truth choice
--       already made for watchlist_companies: filters are edited in the
--       database or the UI, never in a deployed script.
--    c) email_daily on the criteria row, not on the profile. A person can
--       have three saved searches and want email for only one of them.
--    d) last_sent_at for the digest watermark and for spotting a stalled job.
-- ---------------------------------------------------------------------------
create table if not exists public.user_criteria (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  name         text not null default 'My search',
  filters      jsonb not null default '{}'::jsonb,
  email_daily  boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  last_sent_at timestamptz
);

-- RLS predicates hit user_id on every query.
create index if not exists user_criteria_user_id_idx
  on public.user_criteria (user_id);

-- The digest job selects on this. Partial, so the index stays small: it only
-- contains the rows that actually want email.
create index if not exists user_criteria_email_daily_idx
  on public.user_criteria (email_daily)
  where email_daily;

alter table public.user_criteria enable row level security;

create policy user_criteria_select_own on public.user_criteria
  for select using ( (select auth.uid()) = user_id );

create policy user_criteria_insert_own on public.user_criteria
  for insert with check ( (select auth.uid()) = user_id );

create policy user_criteria_update_own on public.user_criteria
  for update using ( (select auth.uid()) = user_id )
  with check ( (select auth.uid()) = user_id );

create policy user_criteria_delete_own on public.user_criteria
  for delete using ( (select auth.uid()) = user_id );

-- ---------------------------------------------------------------------------
-- 4. Grants. RLS filters rows; GRANT decides whether the role may touch the
--    table at all. Both are required. Forgetting the grant produces a
--    permission error that looks nothing like a policy problem.
--
--    anon gets nothing. These tables are for logged-in users only.
-- ---------------------------------------------------------------------------
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.user_criteria to authenticated;

-- Note: the service_role key used by GitHub Actions bypasses RLS entirely.
-- The digest job relies on that to read every user's criteria. It is also why
-- that key must never appear in any file served from heymeyer.com. The anon
-- key in the private page is fine and expected: the session grants access,
-- not the key.
