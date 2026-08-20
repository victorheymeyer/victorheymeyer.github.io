(function () {
  "use strict";

  if (window.__telemetryLoaded) return;
  window.__telemetryLoaded = true;

  var SUPABASE_URL = "https://gfwzdluwljtcbvmmkktd.supabase.co";
  var ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdmd3pkbHV3bGp0Y2J2bW1ra3RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2ODA2MjcsImV4cCI6MjA5ODI1NjYyN30.bGjryWzUobX--FFFmBPlEorY8Tb9qpm_aGDEW0ApBps";
  var SESSION_TIMEOUT_MS = 30 * 60 * 1000;
  var VISITOR_KEY = "th_visitor_id";
  var SESSION_KEY = "th_session_id";
  var LAST_ACTIVE_KEY = "th_last_active";
  var BOT_RE = /bot|crawl|spider|slurp|mediapartners|headless|phantom|selenium/i;
  var CDN_SRC = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";

  function uuid() {
    if (window.crypto && window.crypto.randomUUID) return window.crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = (Math.random() * 16) | 0;
      var v = c === "x" ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function getVisitorId() {
    try {
      var id = localStorage.getItem(VISITOR_KEY);
      if (!id) {
        id = uuid();
        localStorage.setItem(VISITOR_KEY, id);
      }
      return id;
    } catch (e) {
      return null;
    }
  }

  function getSessionId() {
    try {
      var now = Date.now();
      var id = localStorage.getItem(SESSION_KEY);
      var last = Number(localStorage.getItem(LAST_ACTIVE_KEY) || 0);
      if (!id || !last || now - last > SESSION_TIMEOUT_MS) {
        id = uuid();
        localStorage.setItem(SESSION_KEY, id);
      }
      localStorage.setItem(LAST_ACTIVE_KEY, String(now));
      return id;
    } catch (e) {
      return null;
    }
  }

  function baseFields() {
    return {
      visitor_id: getVisitorId(),
      session_id: getSessionId(),
      user_agent: navigator.userAgent || null,
      ua_bot: BOT_RE.test(navigator.userAgent || ""),
      nav_webdriver: navigator.webdriver === true
    };
  }

  function start(client) {
    function send(row) {
      if (!client) return;
      try {
        client.from("event_logs").insert(row).then(function () {}, function () {});
      } catch (e) {
        // telemetry must never break the page
      }
    }

    function trackPageview() {
      var row = baseFields();
      row.event_type = "pageview";
      row.page_url = window.location.href;
      row.referrer = document.referrer || null;
      send(row);
    }

    function trackClick(anchor) {
      var row = baseFields();
      row.event_type = "click";
      row.page_url = window.location.href;
      row.target_url = anchor.href;
      var company = anchor.getAttribute("data-company");
      var atsId = anchor.getAttribute("data-ats-id");
      if (company) row.watchlist_company = company;
      if (atsId) row.ats_id = atsId;
      send(row);
    }

    document.addEventListener("click", function (e) {
      try {
        var anchor = e.target && e.target.closest ? e.target.closest("a[href]") : null;
        if (anchor) trackClick(anchor);
      } catch (err) {
        // swallow
      }
    }, true);

    try {
      trackPageview();
    } catch (e) {
      // swallow
    }
  }

  function createClientAndStart() {
    var client = null;
    try {
      if (window.supabase && window.supabase.createClient) {
        // Never read or persist an auth session here: telemetry must always
        // write as anon, even when the visitor is signed in elsewhere on the
        // site. supabase-js otherwise shares one localStorage session across
        // every client on this project, which would silently upgrade these
        // inserts to the authenticated role and get rejected (anon is the
        // only role granted INSERT on event_logs).
        client = window.supabase.createClient(SUPABASE_URL, ANON_KEY, {
          auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
        });
      }
    } catch (e) {
      client = null;
    }
    start(client);
  }

  function ensureSupabaseThenStart() {
    if (window.supabase && window.supabase.createClient) {
      createClientAndStart();
      return;
    }
    try {
      var existing = document.querySelector('script[src="' + CDN_SRC + '"]');
      if (existing) {
        existing.addEventListener("load", createClientAndStart);
        existing.addEventListener("error", function () {});
        return;
      }
      var script = document.createElement("script");
      script.src = CDN_SRC;
      script.onload = createClientAndStart;
      script.onerror = function () {
        // telemetry must never break the page
      };
      document.head.appendChild(script);
    } catch (e) {
      // swallow
    }
  }

  ensureSupabaseThenStart();
})();
