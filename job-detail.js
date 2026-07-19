// Shared job detail panel for victorheymeyer.github.io/projects/watchlist-jobs.
// Every page that shows an expandable job row builds it by calling
// JobDetail.render() instead of keeping its own copy of this markup.
(function () {
  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
  function cssId(s) { return s.replace(/[^a-z0-9]/gi, "_"); }

  function fmtDate(d) {
    if (!d) return "";
    const dt = new Date(d);
    if (isNaN(dt)) return d;
    return dt.toISOString().slice(0, 10);
  }

  function fmtSalary(r) {
    if (r.salary_min == null && r.salary_max == null) return "";
    const cur = r.salary_currency || "";
    const n = (v) => v == null ? "" : Number(v).toLocaleString();
    if (r.salary_min != null && r.salary_max != null) return cur + " " + n(r.salary_min) + " to " + n(r.salary_max);
    return cur + " " + n(r.salary_min != null ? r.salary_min : r.salary_max);
  }

  // A requisition code is a short token of uppercase letters/digits/hyphens that
  // contains at least one digit (e.g. FEQ227R42, CSQ327R31, SLSQ227R53, P-156).
  function isReqCode(text) {
    const t = (text || "").trim();
    return t.length > 0 && t.length <= 16 && /^[A-Z][A-Z0-9-]*\d[A-Z0-9-]*$/.test(t);
  }

  // Remove the first block whose only content is a req code, wrapper and all, so no
  // empty paragraph is left behind. Falls back to a text-level strip if there's no wrapper.
  function stripLeadingReqCode(safeHtml) {
    const wrap = document.createElement("div");
    wrap.innerHTML = safeHtml;
    // skip empty leading nodes, then test the first element with text
    let node = wrap.firstChild;
    while (node && node.nodeType === 3 && !node.textContent.trim()) node = node.nextSibling;
    if (node && node.nodeType === 1 && isReqCode(node.textContent)) {
      node.remove();
      return wrap.innerHTML;
    }
    // no wrapper: code may be bare leading text inside the first element or root
    if (node && node.nodeType === 1) {
      node.innerHTML = node.innerHTML.replace(/^\s*[A-Z][A-Z0-9-]*\d[A-Z0-9-]*(?:&nbsp;|\s)+/, "");
    } else if (node && node.nodeType === 3) {
      node.textContent = node.textContent.replace(/^\s*[A-Z][A-Z0-9-]*\d[A-Z0-9-]*\s+/, "");
    }
    return wrap.innerHTML;
  }

  // Turn plain text into paragraphs and bullet lists. Double newlines split blocks,
  // single newlines become line breaks, and lines starting with - / • / * become list items.
  function plainTextToHtml(text) {
    const blocks = text.split(/\n{2,}/).map(b => b.trim()).filter(Boolean);
    let html = "", inList = false;
    for (const b of blocks) {
      if (/^[-•*]\s+/.test(b)) {
        if (!inList) { html += "<ul>"; inList = true; }
        html += "<li>" + esc(b.replace(/^[-•*]\s+/, "")).replace(/\n/g, "<br>") + "</li>";
      } else {
        if (inList) { html += "</ul>"; inList = false; }
        html += "<p>" + esc(b).replace(/\n/g, "<br>") + "</p>";
      }
    }
    if (inList) html += "</ul>";
    return html;
  }

  // Display-time render: render to safe HTML, then drop a leading requisition-code
  // block. Handles both real HTML (Greenhouse/Ashby now) and legacy plain text with
  // newlines/bullets. General, not tied to current formats. Storage stays raw.
  function renderDescription(html) {
    if (!html) return "";
    // decide whether this is real HTML or plain text (a bare "<500" is not a tag)
    const looksHtml = /<\/?(p|br|div|ul|ol|li|strong|b|em|i|span|h[1-6]|a|table|tr|td)\b/i.test(html);
    const safe = DOMPurify.sanitize(looksHtml ? html : plainTextToHtml(html),
      { USE_PROFILES: { html: true }, FORBID_ATTR: ["style"], FORBID_TAGS: ["font"] });
    return stripLeadingReqCode(safe);
  }

  // descriptionHtml: undefined -> not fetched yet (loading state); null/"" -> fetched,
  // nothing stored; non-empty string -> raw HTML/text to sanitize and render.
  function descriptionBlock(descriptionHtml) {
    if (descriptionHtml === undefined) return "Loading description...";
    if (!descriptionHtml) return "No description stored for this role.";
    return renderDescription(descriptionHtml);
  }

  // location: undefined -> not fetched yet; null/"" -> fetched, nothing stored.
  function locationBlock(location) {
    if (location === undefined) return "Loading...";
    return esc(location || "N/A");
  }

  // row is a jobs_location_flags row. descriptionHtml/location come from the
  // job_content table (a separate query the caller owns) and are optional -
  // omit both for the initial synchronous insert, then call render() again with
  // both once the caller's fetch resolves and replace the placeholder element.
  function render(row, descriptionHtml, location) {
    const r = row;
    const key = r.watchlist_company + "::" + r.ats_id;

    const dept = r.department ? esc(r.department) : "N/A";
    const team = r.team ? esc(r.team) : "N/A";
    const posted = r.posted_at ? fmtDate(r.posted_at) : "N/A";
    const lastSeen = fmtDate(r.snapshot_date);
    const firstSeen = r.first_seen ? fmtDate(r.first_seen) : "N/A";
    const ats = r.ats_type ? esc(r.ats_type) : "N/A";
    const atsId = esc(r.ats_id || "");
    const lastDescChange = r.description_last_change ? fmtDate(r.description_last_change) : "-";
    const descChangeCount = r.description_change_count != null ? r.description_change_count : "-";

    const disc = r.discipline ? esc(r.discipline) : "-";
    const roleKw = r.role_keyword ? esc(r.role_keyword) : "-";
    const lvl = r.level ? esc(r.level) : "-";

    const employmentType = r.employment_type ? esc(r.employment_type) : "N/A";
    const isRemoteLabel = r.is_remote === true ? "Yes" : (r.is_remote === false ? "No" : "N/A");
    const salary = fmtSalary(r) || "N/A";

    const meta =
      '<div class="metaline"><span class="lbl">Job Info:</span> Dept: ' + dept +
        ' | Team: ' + team +
        ' | Location: <span class="locval">' + locationBlock(location) + '</span></div>' +
      '<div class="metaline"><span class="lbl">Classification:</span> Discipline: ' + disc +
        ' | Role: ' + roleKw +
        ' | Level: ' + lvl + '</div>' +
      '<div class="metaline"><span class="lbl">Dates:</span> Posted: ' + posted +
        ' | Last Seen: ' + lastSeen +
        ' | First Seen: ' + firstSeen +
        ' | Last Desc Change: ' + lastDescChange +
        ' | Char # delta: ' + descChangeCount + '</div>' +
      '<div class="metaline"><span class="lbl">Other:</span> Type: ' + employmentType +
        ' | Remote: ' + isRemoteLabel +
        ' | Salary: ' + salary + '</div>' +
      '<div class="metaline"><span class="lbl">ATS:</span> ' + ats +
        ' | ATS Job ID: ' + atsId + '</div>';

    const tr = document.createElement("tr");
    tr.className = "detail job-detail";
    const td = document.createElement("td");
    td.innerHTML = '<div class="meta">' + meta + '</div><div class="desc" id="desc_' + cssId(key) + '">' +
      descriptionBlock(descriptionHtml) + '</div>';
    tr.appendChild(td);
    return tr;
  }

  window.JobDetail = { render: render, esc: esc };
})();
