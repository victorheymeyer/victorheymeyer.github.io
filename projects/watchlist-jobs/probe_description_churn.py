# projects/watchlist-jobs/probe_description_churn.py
"""
Pre-cutover probe for the jobhive-py -> ats-scrapers migration (handoff §9,
step 1): fetch a live sample from the watchlist using the new ats-scrapers
library, and compare against what's already stored in job_content.

The comparison MUST run description_fingerprint() over both sides -- the
freshly fetched description AND the description already stored in
job_content -- and compare those two fingerprint hashes. Comparing the fresh
fingerprint against the stored current_description_hash instead (which was
written by the OLD jobhive-based algorithm, never passed through
description_fingerprint) would make every row read as "changed" regardless
of whether the content actually moved, since the hashing algorithm itself
changed. Putting both sides through the same normalizer isolates real
content drift (or a scraper-library behavior change, e.g. Ashby now
preferring descriptionHtml) from that algorithm-switch noise.

Read-only: does not write to job_content or raw_watchlist_jobs.

Usage:
  python probe_description_churn.py                   # one company per ATS
  python probe_description_churn.py --all              # every active company
  python probe_description_churn.py acme,other-corp    # named companies only
"""
import hashlib
import sys
from collections import defaultdict

from fetch_watchlist_jobs import SCRAPERS, description_fingerprint, sb


def pick_sample_companies(only_names=None, all_companies=False):
    resp = sb.table("watchlist_companies") \
        .select("company,ats,slug,scraper_kwargs") \
        .eq("active", True) \
        .order("priority") \
        .execute()
    rows = resp.data or []
    if only_names:
        wanted = {n.strip() for n in only_names}
        return [r for r in rows if r["company"] in wanted]
    if all_companies:
        return rows
    # Default: one representative company per distinct ATS (first by
    # priority), so a single run covers every scraper actually on the
    # watchlist -- including Lever and Workday, not just the original eight.
    seen_ats = set()
    sample = []
    for r in rows:
        ats = (r["ats"] or "").lower()
        if ats not in seen_ats:
            seen_ats.add(ats)
            sample.append(r)
    return sample


def compute_hash(description):
    fingerprint = description_fingerprint(description)
    return hashlib.sha256(fingerprint.encode("utf-8")).hexdigest() if fingerprint else None


def load_stored_descriptions(company, ats_ids):
    """Raw job_content.description for each ats_id -- the OLD library's last
    stored capture -- so it can be re-fingerprinted with the NEW normalizer
    for a like-for-like comparison against today's fresh fetch.
    """
    stored = {}
    for i in range(0, len(ats_ids), 200):
        chunk = ats_ids[i:i + 200]
        resp = sb.table("job_content") \
            .select("ats_id,description") \
            .eq("watchlist_company", company) \
            .in_("ats_id", chunk) \
            .execute()
        for r in resp.data or []:
            stored[r["ats_id"]] = r["description"]
    return stored


def main():
    args = sys.argv[1:]
    all_companies = "--all" in args
    names = [a for a in args if not a.startswith("--")]
    only_names = names[0].split(",") if names else None

    companies = pick_sample_companies(only_names=only_names, all_companies=all_companies)
    if not companies:
        print("No matching companies found in watchlist_companies.")
        return

    print(f"Probing {len(companies)} companies: "
          + ", ".join(f"{c['company']}/{c['ats']}" for c in companies) + "\n")

    # new       = ats_id not seen before (no stored description to compare
    #             against -- excluded from the churn %)
    # no_desc   = today's fresh fetch came back empty (scraper miss, excluded)
    # no_stored = job_content.description is NULL for this ats_id (nulled by
    #             null_non_seattle_description, or never captured -- nothing
    #             to re-fingerprint, excluded)
    # changed   = fingerprint(fresh) != fingerprint(stored) -- real content
    #             drift or a scraper-library behavior change, NOT algorithm
    #             noise, since both sides go through the same normalizer
    stats = defaultdict(lambda: {"total": 0, "changed": 0, "new": 0, "no_desc": 0, "no_stored": 0})
    failures = []

    for entry in companies:
        company, ats, slug = entry["company"], (entry["ats"] or "").lower(), entry["slug"]
        scraper_kwargs = entry.get("scraper_kwargs") or {}
        if ats not in SCRAPERS:
            print(f"SKIP {company:12s}: unknown ats '{ats}'")
            continue
        try:
            jobs = SCRAPERS[ats](slug, **scraper_kwargs).fetch()
        except Exception as e:
            print(f"FAIL {company:12s} ({ats}/{slug}): {type(e).__name__}: {e}")
            failures.append(company)
            continue

        dumped = [j.model_dump(mode="json") for j in jobs]
        ats_ids = [str(d.get("ats_id")) for d in dumped]
        stored = load_stored_descriptions(company, ats_ids)

        s = stats[ats]
        for d in dumped:
            ats_id = str(d.get("ats_id"))
            fresh_description = d.get("description")
            s["total"] += 1
            if fresh_description is None:
                s["no_desc"] += 1
                continue
            if ats_id not in stored:
                s["new"] += 1
                continue
            stored_description = stored[ats_id]
            if stored_description is None:
                s["no_stored"] += 1
                continue
            if compute_hash(fresh_description) != compute_hash(stored_description):
                s["changed"] += 1

        print(f"OK   {company:12s} ({ats}/{slug}): {len(jobs)} jobs fetched")

    print("\nChurn rate per ATS (before any write):")
    print(f"{'ATS':12s} {'jobs':>6s} {'new':>6s} {'no_desc':>8s} {'no_stored':>9s} {'changed':>8s} {'churn %':>8s}")
    for ats, s in sorted(stats.items()):
        comparable = s["total"] - s["new"] - s["no_desc"] - s["no_stored"]
        pct = (100.0 * s["changed"] / comparable) if comparable else 0.0
        print(f"{ats:12s} {s['total']:6d} {s['new']:6d} {s['no_desc']:8d} "
              f"{s['no_stored']:9d} {s['changed']:8d} {pct:7.1f}%")

    if failures:
        print(f"\nFAILED to fetch: {failures}")


if __name__ == "__main__":
    main()
