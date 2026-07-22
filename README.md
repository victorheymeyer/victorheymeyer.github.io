Source for my personal website, [heymeyer.com](https://heymeyer.com), a home for my projects.

Main Digital Project:  as of July 2026  
**Seattle Jobs** – daily snapshot of **new** job listings in Seattle focused on the technology sector.  

Each digital project follows the same pattern: a scheduled GitHub Actions job pulls data from a public source, stores daily snapshots in Supabase, and a static page reads from Supabase to show summaries, trends, and interactive views. Hosted on GitHub Pages.   

****Built with assistance from:** Claude Chat, and Claude Code

**Data Sources:**
- **LLM Pricing:** LiteLLM's model_prices_and_context_window.json from the BerriAI/litellm repo
- **Company ATS and careers APIs:** Examples: Greenhouse, Ashby, Google, Eightfold/Microsoft, and Workday

**Tools & Infrastructure:**
- **Research**: Gemini Pro
- **Testing:** Google Colab
- **Repo/Version Control:** Git and GitHub
- **Editor:** VS Code
- **Web scraping:** JobHive (`jobhive-py`) - Open Source package/public repo
- **Storage & Schema Migration:** Supabase & Supabase CLI
- **Continuous Integration/Deployment:** GitHub Actions
- **Hosting:** GitHub Pages
- **Email:** Resend - WIP
- **LLM Scoring:** DeepSeek (V4 Flash, V4 Pro) and Claude (Sonnet 5) - WIP
- **Python libraries:** requests, httpx, html2text, openpyxl
- **Frontend libraries (via jsDelivr CDN):** Supabase JS client, DOMPurify, Chart.js, marked
