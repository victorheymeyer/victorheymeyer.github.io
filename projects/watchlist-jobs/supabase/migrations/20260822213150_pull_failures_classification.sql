alter table pull_failures
  add column if not exists error_code text,
  add column if not exists outcome    text;
-- Constrain to the locked vocabularies. Nullable (old rows stay NULL; that is
-- fine — they predate classification and are pruned within days anyway).
alter table pull_failures
  add constraint pull_failures_error_code_ck
    check (error_code is null or error_code in (
      'RATE_LIMITED','CHALLENGE','TIMEOUT','TRANSIENT',
      'NOT_FOUND','FORBIDDEN','SERVER_ERROR','CONFIG','OTHER'
    )),
  add constraint pull_failures_outcome_ck
    check (outcome is null or outcome in ('BLOCKED','REMOVED','ERROR','CONFIG'));
