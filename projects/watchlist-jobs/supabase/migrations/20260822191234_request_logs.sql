create table request_logs (
  id              bigint generated always as identity primary key,
  run_date        date        not null,
  requested_at    timestamptz not null default now(),
  company         text        not null,
  ats             text        not null,
  host            text        not null,
  request_kind    text        not null default 'listing',   -- listing | description
  attempts        int         not null,                     -- total tries
  failed_attempts int         not null,                     -- tries that failed; row written when >= 1
  http_status     int,                                       -- final attempt's status; null if no HTTP response
  outcome         text        not null,                      -- OK = recovered after failures; else final failure
  error_code      text        not null,                      -- nature of the failure(s)
  detail          text,                                       -- free-text specifics
  constraint request_logs_outcome_ck
    check (outcome in ('OK','BLOCKED','REMOVED','ERROR')),
  constraint request_logs_error_code_ck
    check (error_code in (
      'OK','RATE_LIMITED','CHALLENGE','TIMEOUT',
      'NOT_FOUND','FORBIDDEN','SERVER_ERROR','OTHER'
    ))
);
create index request_logs_run_host_idx on request_logs (run_date, host);
create index request_logs_company_idx  on request_logs (company, run_date);
create index request_logs_outcome_idx  on request_logs (run_date, outcome);

alter table request_logs enable row level security;
