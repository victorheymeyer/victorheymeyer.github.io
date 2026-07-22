-- Waitlist signup (v1): email-first demand capture for the Seattle job
-- board. One table, locked down with RLS; the anon client never touches it
-- directly, only through the two SECURITY DEFINER RPCs below.
--
-- waitlist_join is intentionally NOT granted to anon. The frontend calls it
-- through the waitlist-join edge function, which verifies a Cloudflare
-- Turnstile token first and then calls this RPC using the service role key.
-- That's what makes Turnstile actually gate the write instead of being
-- theater a scripted client could bypass by hitting the RPC directly.
--
-- waitlist_set_category IS granted to anon: it only overwrites the category
-- on an already-created row for a known email, which is a low-stakes,
-- accepted v1 tradeoff (anyone who knows an address could set its category).

create table if not exists public.waitlist_signups (
  id           bigint generated always as identity primary key,
  email        text not null,
  job_category text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint waitlist_signups_job_category_check check (
    job_category is null or job_category = any (array[
      'Software Engineering',
      'Data & Analytics',
      'Product Management',
      'Design',
      'Program / Project Management',
      'Finance',
      'Marketing',
      'Sales / Business Development',
      'Recruiting / People',
      'Operations',
      'Other'
    ])
  )
);

-- Case-insensitive uniqueness so the same address cannot pad the count.
create unique index if not exists waitlist_signups_email_uidx
  on public.waitlist_signups (lower(email));

-- Lock the table: RLS on, no anon policies => anon has zero direct access.
alter table public.waitlist_signups enable row level security;

-- Join RPC: normalize, validate, idempotent insert. Returns true if a NEW
-- row was created, false if the email was already on the list -- a clean
-- "new signups" signal that leaks nothing back to the caller.
create or replace function public.waitlist_join(p_email text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
begin
  if v_email is null
     or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email';
  end if;

  insert into public.waitlist_signups (email)
  values (v_email)
  on conflict (lower(email)) do nothing;

  return found;
end;
$$;

revoke all on function public.waitlist_join(text) from public;
grant execute on function public.waitlist_join(text) to service_role;

-- Set-category RPC: updates the same row. WHERE clause is required (pg
-- safeupdate blocks an UPDATE without one via RPC).
create or replace function public.waitlist_set_category(p_email text, p_category text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
begin
  update public.waitlist_signups
     set job_category = p_category,
         updated_at   = now()
   where lower(email) = v_email;
end;
$$;

revoke all on function public.waitlist_set_category(text, text) from public;
grant execute on function public.waitlist_set_category(text, text) to anon;
