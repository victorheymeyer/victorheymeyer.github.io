// Shared site footer for victorheymeyer.github.io
// Edit here to change the footer on every page that loads this script.
(function () {
  const footer = document.createElement("footer");
  footer.className = "site-footer";

  const p = document.createElement("p");
  p.appendChild(document.createTextNode("© 2026 Victor Heymeyer | Seattle, WA | "));
  const linkedin = document.createElement("a");
  linkedin.href = "https://www.linkedin.com/in/heymeyer/";
  linkedin.target = "_blank";
  linkedin.rel = "noopener noreferrer";
  linkedin.textContent = "LinkedIn";
  p.appendChild(linkedin);
  p.appendChild(document.createTextNode(" | "));
  const github = document.createElement("a");
  github.href = "https://github.com/victorheymeyer";
  github.target = "_blank";
  github.rel = "noopener noreferrer";
  github.textContent = "GitHub";
  p.appendChild(github);
  p.appendChild(document.createTextNode(" "));
  footer.appendChild(p);

  const right = document.createElement("a");
  right.className = "footer-right";
  right.href = "https://heymeyer.com";
  right.target = "_blank";
  right.rel = "noopener noreferrer";
  right.textContent = "heymeyer.com";
  footer.appendChild(right);

  // Mount into a <div id="siteFooter"></div> placeholder if present, else append to body.
  const mount = document.getElementById("siteFooter");
  if (mount) mount.replaceWith(footer);
  else document.body.appendChild(footer);
})();
