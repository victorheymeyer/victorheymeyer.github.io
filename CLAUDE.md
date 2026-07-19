# victorheymeyer.github.io

- The job detail panel is defined once in /job-detail.js and styled in
  styles.css (the "Job detail panel" section). Any page showing job details
  must call JobDetail.render() rather than writing its own markup — never
  inline a copy.
- API keys and secrets live in GitHub Actions secrets only, never client-side.
  The Supabase anon key is the only key allowed in browser code.
