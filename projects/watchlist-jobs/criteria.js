// Shared saved-criteria storage + resolution, used by both
// /projects/watchlist-jobs/my-jobs.html and /projects/watchlist-jobs/my-criteria.html.
// Keeping this in one place means both pages agree on how a signed-in row
// vs. a guest's local blob is read, merged, and written - notably the
// "signed-in" / "local" / "none" uiState split and the local->account
// migration on first sign-in, which only need to happen once, correctly,
// no matter which page a person lands on first.
//
// Must be loaded with a plain (non-deferred) <script src="..."> tag, after
// the Supabase CDN script and before any inline script that reads
// window.Criteria - it runs immediately at parse time and needs
// window.supabase to already exist.
(function () {
  const SUPABASE_URL = "https://gfwzdluwljtcbvmmkktd.supabase.co";
  const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdmd3pkbHV3bGp0Y2J2bW1ra3RkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI2ODA2MjcsImV4cCI6MjA5ODI1NjYyN30.bGjryWzUobX--FFFmBPlEorY8Tb9qpm_aGDEW0ApBps";

  const supabaseClient = window.supabase.createClient(SUPABASE_URL, ANON_KEY);

  const LOCAL_STORAGE_KEY = "watchlist_filters";
  // Sentinel for the "(unclassified)" option in classifier checklists/dropdowns
  // (matches rows where discipline/role_keyword/level is null).
  const UNCLASSIFIED = "__unclassified__";

  function defaultFilters() {
    return { company: "", wa: false, remote: false, search: "", discipline: [], role: [], level: [], daysOld: [], postStatus: [] };
  }

  // Merge a saved blob over the default shape so a blob missing a key (or an
  // unknown/missing "v") never produces undefined in state.filters. Only the
  // seven persisted keys are read from `saved`; daysOld/postStatus always
  // come from the default (they describe how someone is browsing right now,
  // not what job they want - never part of saved criteria).
  function mergeFilters(saved) {
    const merged = defaultFilters();
    if (saved && typeof saved === "object") {
      if (typeof saved.company === "string") merged.company = saved.company;
      if (typeof saved.wa === "boolean") merged.wa = saved.wa;
      if (typeof saved.remote === "boolean") merged.remote = saved.remote;
      if (typeof saved.search === "string") merged.search = saved.search;
      if (Array.isArray(saved.discipline)) merged.discipline = saved.discipline.slice();
      if (Array.isArray(saved.role)) merged.role = saved.role.slice();
      if (Array.isArray(saved.level)) merged.level = saved.level.slice();
    }
    return merged;
  }

  function persistedBlob(filters) {
    return {
      v: 1,
      company: filters.company, wa: filters.wa, remote: filters.remote, search: filters.search,
      discipline: filters.discipline, role: filters.role, level: filters.level
    };
  }

  // "signed-in" | "local" | "none" - drives the page-level source indicator
  // and whether a Save affordance shows. Signed-in shows even with no saved
  // row yet (an empty row is still "yours"); "local" only when logged out
  // AND a device blob was found; "none" otherwise (a fresh guest).
  const state = {
    uiState: "none",
    currentSession: null,
    currentCriteriaId: null,
    loadedFilters: defaultFilters(),
    // Set only when this load just migrated a local blob into a brand-new
    // account row (first sign-in with device history). Read once by the
    // caller to decide whether to show the one-time seed banner, then never
    // touched again - it is not persisted anywhere, so a reload never
    // re-shows it.
    justSeededFromLocal: false
  };

  // Three sources, in priority order: a signed-in user's row in
  // public.user_criteria; failing that, a localStorage blob from a previous
  // logged-out visit; failing that, empty. Mutates `state` in place and also
  // returns state.loadedFilters for convenience.
  async function resolveCriteria() {
    const { data: { session } } = await supabaseClient.auth.getSession();
    state.currentSession = session;
    if (session) {
      state.uiState = "signed-in";
      let hasRow = false;
      try {
        const { data, error } = await supabaseClient.from("user_criteria").select("id, filters").limit(1);
        if (error) throw error;
        if (data && data.length) {
          state.currentCriteriaId = data[0].id;
          state.loadedFilters = mergeFilters(data[0].filters);
          hasRow = true;
        }
      } catch (err) {
        console.error(err);
        return state.loadedFilters; // read failed: behave as "no row" (empty), never fall back to local.
      }
      if (hasRow) return state.loadedFilters; // session + DB row exists -> load from DB.

      // Session, no DB row yet: migrate a local-device blob in once, rather
      // than silently discarding a guest's work the moment they sign in.
      const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
      if (!raw) return state.loadedFilters; // session, no row, no local blob -> empty (unchanged).

      let localBlob;
      try {
        localBlob = mergeFilters(JSON.parse(raw));
      } catch (err) {
        return state.loadedFilters; // corrupt local blob - nothing to migrate.
      }

      try {
        const { data, error } = await supabaseClient.from("user_criteria")
          .insert({ user_id: session.user.id, filters: persistedBlob(localBlob), updated_at: new Date().toISOString() })
          .select("id").single();
        if (error) throw error;
        // Write succeeded - only now clear the local copy. Never the reverse
        // order, or a failed write would silently lose the guest's criteria.
        state.currentCriteriaId = data.id;
        state.loadedFilters = localBlob;
        localStorage.removeItem(LOCAL_STORAGE_KEY);
        state.justSeededFromLocal = true;
      } catch (err) {
        console.error(err);
        // Write failed: keep the local blob untouched so the next load can
        // retry. No banner, uiState stays "signed-in" as it already was.
      }
      return state.loadedFilters; // signed in: never fall back to localStorage for rendering.
    }

    const raw = localStorage.getItem(LOCAL_STORAGE_KEY);
    if (raw) {
      try {
        state.loadedFilters = mergeFilters(JSON.parse(raw));
        state.uiState = "local";
      } catch (err) {
        // corrupt/foreign blob under this key; ignore and fall through to empty.
      }
    }
    return state.loadedFilters;
  }

  // Silent autosave for guests as they adjust live filters (My Jobs dashboard
  // only - My Criteria uses the explicit saveCriteria() below instead, since
  // Save is meant to be its only write).
  function maybePersistLocal(filters) {
    if (state.uiState === "signed-in") return; // signed-in users save explicitly, to the DB.
    try {
      localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(persistedBlob(filters)));
    } catch (err) {
      return; // storage unavailable/full - filters still work for this session.
    }
    state.uiState = "local";
  }

  // The one explicit write path: signed-in upserts the row, guest writes
  // localStorage. `filters` must be a complete filters object (all seven
  // persisted keys) - a caller that only edits a subset (e.g. My Criteria's
  // discipline/role/level/wa/remote form) must merge onto state.loadedFilters
  // first so fields it doesn't render (company/search) aren't lost.
  async function saveCriteria(filters) {
    const payload = persistedBlob(filters);
    if (state.uiState === "signed-in") {
      if (state.currentCriteriaId) {
        const { error } = await supabaseClient.from("user_criteria")
          .update({ filters: payload, updated_at: new Date().toISOString() })
          .eq("id", state.currentCriteriaId);
        if (error) throw error;
      } else {
        const { data, error } = await supabaseClient.from("user_criteria")
          .insert({ user_id: state.currentSession.user.id, filters: payload, updated_at: new Date().toISOString() })
          .select("id").single();
        if (error) throw error;
        state.currentCriteriaId = data.id;
      }
    } else {
      localStorage.setItem(LOCAL_STORAGE_KEY, JSON.stringify(payload));
      state.uiState = "local";
    }
    state.loadedFilters = mergeFilters(payload);
  }

  const SEED_BANNER_MESSAGE = "The criteria stored on your device has been added to your account and removed from this device. You can edit or clear it anytime while signed in.";

  // Shared markup for the one-time post-migration banner (see
  // justSeededFromLocal above) - both my-jobs.html and my-criteria.html show
  // the identical copy, dismissable, never persisted.
  function renderSeedBanner(el) {
    el.className = "seed-banner";
    el.style.display = "";
    el.innerHTML = "";

    const msg = document.createElement("span");
    msg.textContent = SEED_BANNER_MESSAGE;
    el.appendChild(msg);

    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.className = "seed-banner-dismiss";
    dismiss.setAttribute("aria-label", "Dismiss");
    dismiss.textContent = "×";
    dismiss.onclick = () => { el.style.display = "none"; el.innerHTML = ""; };
    el.appendChild(dismiss);
  }

  window.Criteria = {
    supabaseClient, LOCAL_STORAGE_KEY, UNCLASSIFIED,
    defaultFilters, mergeFilters, persistedBlob,
    state, resolveCriteria, maybePersistLocal, saveCriteria, renderSeedBanner
  };
})();
