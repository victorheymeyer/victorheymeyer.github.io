// Shared site navigation for victorheymeyer.github.io
// Edit SITE_NAV below to add, rename, or reorder pages. Every page that loads
// this script picks up the change automatically. Paths are absolute from the
// domain root, so they work from any page depth.
(function () {
  const BRAND = { label: "Jobs Home", href: "/projects/watchlist-jobs/" };
  const SITE_NAV = [
    { label: "Seattle", href: "/projects/watchlist-jobs/seattle.html" },
    { label: "My Jobs", href: "/projects/watchlist-jobs/my-jobs.html" },
    { label: "Slug Search", href: "/projects/watchlist-jobs/company-search/" },
    { label: "Stats", href: "/projects/watchlist-jobs/stats/index.html" },
    { label: "Tables", href: "/projects/watchlist-jobs/tables/index.html" }
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
    const a = document.createElement("a");
    a.className = "navlink";
    a.href = item.href;
    a.textContent = item.label;
    if (normalize(item.href) === here) a.classList.add("active");
    inner.appendChild(a);
  });

  // Right-aligned external link.
  const right = document.createElement("a");
  right.className = "navlink navright";
  right.href = "https://heymeyer.com";
  right.textContent = "heymeyer.com";
  inner.appendChild(right);

  nav.appendChild(inner);

  // Mount into a <div id="siteNav"></div> placeholder if present, else prepend to body.
  const mount = document.getElementById("siteNav");
  if (mount) mount.replaceWith(nav);
  else document.body.insertBefore(nav, document.body.firstChild);
})();