// Shared site navigation for victorheymeyer.github.io
// Edit SITE_NAV below to add, rename, or reorder pages. Every page that loads
// this script picks up the change automatically. Paths are absolute from the
// domain root, so they work from any page depth.
(function () {
  // Cache-busting: Cloudflare/GitHub Pages cache /site.js and /telemetry.js
  // for hours, so a deploy can leave browsers running stale code long after
  // the new version is live. Bump the ?v= on the <script src="/site.js">
  // tag in each HTML page when site.js or telemetry.js changes; that new
  // URL is a cache miss everywhere, and this line forwards the same query
  // string onto telemetry.js so both scripts bust together from one edit.
  const SCRIPT_VERSION = (document.currentScript && new URL(document.currentScript.src, location.href).search) || "";

  const BRAND = { label: "Seattle Jobs", href: "/projects/watchlist-jobs/" };
  const SITE_NAV = [
    { label: "My Jobs", href: "/projects/watchlist-jobs/my-jobs.html" },
    { label: "My Criteria", href: "/projects/watchlist-jobs/my-criteria.html" },
    { divider: true },
    { label: "Slug Search", href: "/projects/watchlist-jobs/company-search/" },
    { label: "All", href: "/projects/watchlist-jobs/global.html" },
    { label: "Dev", href: "/projects/watchlist-jobs/dev-env/my-jobs" },
    { label: "Stats", href: "/projects/watchlist-jobs/stats/index.html" },
    { divider: true },
    { label: "About", href: "/projects/watchlist-jobs/about.html" }
  ];

  // Treat "/x", "/x/", "/x/index.html", and "/x.html" as the same path for
  // active-link matching. Stripping ".html" (not just "index.html") matters
  // because the local dev server (`serve`) 301s every "/foo.html" request to
  // the extensionless "/foo" - without this, location.pathname ends up
  // extensionless after that redirect while most nav hrefs still carry
  // ".html", so only hrefs that were already extensionless (Dev) or literally
  // named "index.html" (Stats) ever matched and lit up; every other link
  // silently never got its active state locally. Production (GitHub
  // Pages/Cloudflare) doesn't redirect, so this bug never showed up there.
  function normalize(path) {
    return path.replace(/\.html$/, "").replace(/\/index$/, "").replace(/\/+$/, "") || "/";
  }
  const here = normalize(location.pathname);

  const nav = document.createElement("nav");
  nav.className = "site-nav";
  const inner = document.createElement("div");
  inner.className = "inner";

  const brand = document.createElement("a");
  brand.className = "brand";
  brand.href = BRAND.href;
  brand.textContent = BRAND.label;
  inner.appendChild(brand);

  SITE_NAV.forEach(function (item) {
    if (item.divider) {
      const span = document.createElement("span");
      span.className = "navdivider";
      span.textContent = "|";
      inner.appendChild(span);
      return;
    }
    const a = document.createElement("a");
    a.className = "navlink";
    a.href = item.href;
    a.textContent = item.label;
    if (normalize(item.href) === here) a.classList.add("active");
    inner.appendChild(a);
  });

  // Right-aligned auth link: Sign In / Sign Out, mirroring the affordance in
  // my-jobs.html's criteria bar (renderCriteriaBar there) so the whole site
  // reflects the same signed-in state, not just that one page.
  const SUPABASE_URL = "https://gfwzdluwljtcbvmmkktd.supabase.co";
  const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdmd3pkbHV3bGp0Y2J2bW1ra3RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2ODA2MjcsImV4cCI6MjA5ODI1NjYyN30.bGjryWzUobX--FFFmBPlEorY8Tb9qpm_aGDEW0ApBps";

  const right = document.createElement("a");
  right.className = "clearbtn navright";
  inner.appendChild(right);

  function renderSignedOut() {
    right.textContent = "Sign In";
    right.href = "/projects/watchlist-jobs/private/";
    right.onclick = null;
  }
  function renderSignedIn(supabaseClient) {
    right.textContent = "Sign Out";
    right.href = "#";
    right.onclick = async (e) => {
      e.preventDefault();
      right.onclick = null;
      await supabaseClient.auth.signOut();
      location.reload();
    };
  }
  renderSignedOut();

  if (window.supabase) {
    const supabaseClient = window.supabase.createClient(SUPABASE_URL, ANON_KEY);
    supabaseClient.auth.getSession().then(({ data }) => {
      if (data.session) renderSignedIn(supabaseClient);
    });
    supabaseClient.auth.onAuthStateChange((_event, session) => {
      if (session) renderSignedIn(supabaseClient);
      else renderSignedOut();
    });
  }

  nav.appendChild(inner);

  // Nav injection is opt-in: only replace a <div id="siteNav"></div> mount if
  // the page has one. Pages without a mount get no nav from this script.
  const mount = document.getElementById("siteNav");
  if (mount) mount.replaceWith(nav);

  // Every page that loads site.js gets telemetry automatically, so no page
  // needs its own <script src="/telemetry.js"> tag. Guarded so the loader
  // never adds a second copy.
  if (!document.querySelector('script[src="/telemetry.js"]')) {
    const telemetry = document.createElement("script");
    telemetry.defer = true;
    telemetry.src = "/telemetry.js" + SCRIPT_VERSION;
    document.head.appendChild(telemetry);
  }
})();