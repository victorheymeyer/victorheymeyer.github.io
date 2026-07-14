-- ARCHIVE ONLY. Not a replayable migration.
--
-- Recovered from supabase_migrations.schema_migrations on the jobs-tracker
-- project (gfwzdluwljtcbvmmkktd) before the migration history table was
-- repaired and a baseline snapshot was taken via `supabase db pull`.
--
-- These 16 statements were applied to the live database between 2026-07-10 and
-- 2026-07-13 (by Claude Code via the Supabase MCP apply_migration tool). They
-- assume base tables that were created by hand in the SQL editor and were never
-- captured in any migration, so this set CANNOT be replayed against an empty
-- database. Their effects are already folded into the baseline migration in
-- supabase/migrations/. Kept for the record, not for execution.
--
-- version: 20260713025132
-- name:    create_target_filter_rules


create table public.target_filter_rules (
  category   text not null check (category in ('discipline','role','level')),
  value      text not null,          -- discipline / role_keyword / level string,
                                      -- or '__unclassified__' to match NULL
  created_at timestamptz not null default now(),
  primary key (category, value)
);

alter table public.target_filter_rules enable row level security;

create policy "public read target_filter_rules" on public.target_filter_rules
  for select to anon using (true);

grant select on public.target_filter_rules to anon;

insert into public.target_filter_rules (category, value) values
  ('discipline','Data & Analytics'),
  ('discipline','Product Management'),
  ('discipline','Project/Program Management'),
  ('discipline','Sales'),
  ('discipline','Marketing'),
  ('discipline','Finance'),
  ('discipline','Strategy'),
  ('discipline','Operations'),
  ('discipline','Customer Success'),
  ('discipline','Other'),
  ('role','Chief of Staff'),
  ('role','Product Manager'),
  ('role','Program Manager'),
  ('role','Data Analyst/Analysis'),
  ('role','Product Management'),
  ('role','Finance & Strategy'),
  ('role','Strategy & Operations'),
  ('role','Business Planner/Planning'),
  ('role','Consultant'),
  ('role','Strategist'),
  ('role','Product Strategy'),
  ('role','Strategy'),
  ('role','Strategic Finance'),
  ('role','Corp Dev'),
  ('role','Biz Dev'),
  ('role','Customer Success'),
  ('role','Marketing'),
  ('role','Financial Planning'),
  ('role','Financing'),
  ('role','Treasury'),
  ('role','Analytics (Other)'),
  ('role','Finance (Other)'),
  ('role','Analyst (Other)'),
  ('role','GTM (other)'),
  ('role','Operations (other)'),
  ('role','Program (Other)'),
  ('role','Planning (other)'),
  ('role','Analysis (other)'),
  ('role','__unclassified__'),
  ('level','CXO'),
  ('level','VP'),
  ('level','GM'),
  ('level','Chief of Staff'),
  ('level','Senior Director'),
  ('level','Director'),
  ('level','Head of'),
  ('level','Senior Principal'),
  ('level','Principal'),
  ('level','Staff'),
  ('level','Lead');
