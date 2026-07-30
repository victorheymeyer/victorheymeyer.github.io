Watchlist Jobs

General Overview: A daily job tracker for Seattle-area and remote-Washington roles. It scrapes public ATS boards (e.g. Greenhouse, Ashby, Lever, Workday) across hundreds of companies and surfaces new Seattle openings on a single dashboard, filtered by personal criteria.

Technical Summary: A Python loader pulls each company's live board once a day, normalizes the postings, and writes a dated snapshot to Supabase. Titles are auto-classified by discipline, role, and seniority level. A GitHub Actions cron job runs the loader daily.
