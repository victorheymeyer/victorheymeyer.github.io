-- delete_stale() in build_company_directory.py deletes rows with a stale
-- updated_at after each ATS refresh, which needs DELETE privilege -- missed
-- in the original grant (SELECT/INSERT/UPDATE only), causing the monthly
-- Company Directory workflow to fail with "permission denied for table
-- ats_company_directory" after the upsert step already succeeded.
grant delete on public.ats_company_directory to service_role;
