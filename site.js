// Shared site navigation for victorheymeyer.github.io
// Edit SITE_NAV below to add, rename, or reorder pages. Every page that loads
// this script picks up the change automatically. Paths are absolute from the
// domain root, so they work from any page depth.
(function () {
  const BRAND = { label: "Seattle Jobs", href: "/projects/watchlist-jobs/" };
  const SITE_NAV = [
    { label: "My Jobs", href: "/projects/watchlist-jobs/my-jobs.html" },
    { label: "My Criteria", href: "/projects/watchlist-jobs/my-criteria.html" },
    { divider: true },
    { label: "Slug Search", href: "/projects/watchlist-jobs/company-search/" },
    { label: "Global", href: "/projects/watchlist-jobs/global.html" },
    { label: "Stats", href: "/projects/watchlist-jobs/stats/index.html" }
  ];

  // Treat "/x", "/x/", and "/x/index.html" as the same path for active-link matching.
  function normalize(path) {
    return path.replace(/index\.html$/, "").replace(/\/+$/, "") || "/";
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

  // Mount into a <div id="siteNav"></div> placeholder if present, else prepend to body.
  const mount = document.getElementById("siteNav");
  if (mount) mount.replaceWith(nav);
  else document.body.insertBefore(nav, document.body.firstChild);
})();