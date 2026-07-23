# projects/watchlist-jobs/fetch_watchlist_jobs.py
import hashlib
import html as html_mod
import os
import re
import sys
from datetime import datetime, timedelta, timezone

from ats_scrapers.scrapers import GreenhouseScraper, AshbyScraper, AmazonScraper, AppleScraper, GoogleScraper, TikTokScraper, UberScraper, EightfoldScraper, LeverScraper, WorkdayScraper
from supabase import create_client

SUPABASE_URL = os.environ["JOBS_SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["JOBS_SUPABASE_SERVICE_KEY"]
sb = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

SCRAPERS = {
    "greenhouse": GreenhouseScraper,
    "ashby": AshbyScraper,
    "amazon": AmazonScraper,
    "apple": AppleScraper,
    "google": GoogleScraper,
    "tiktok": TikTokScraper,
    "uber": UberScraper,
    "eightfold": EightfoldScraper,
    "lever": LeverScraper,
    "workday": WorkdayScraper,
}

# --- Description fingerprint (hash re-anchoring) ------------------------------
# The hash that gates the LLM scoring pipeline must not be a field a third
# party defines. ats-scrapers decides the shape of Job.description on its own
# terms (HTML for Greenhouse, HTML-preferred for Ashby, plain text for others)
# and that shape already moved once across a version bump -- jobhive-py 0.1.0
# gave Greenhouse/Ashby as stripped plain text; ats-scrapers 0.2.0 gives HTML.
# Hashing description_fingerprint()'s output instead of the raw field means a
# future upstream formatting change can't silently rewrite every hash again.
#
# Storage of job_content.description is unchanged: raw HTML still goes in.
# Only the hash input changes.

HASH_ALGO = "plain-v1"

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def description_fingerprint(value):
    """Deterministic plain-text projection used ONLY for change detection.

    Strip tags first so escaped angle brackets survive as literal text, then
    unescape entities, then collapse all whitespace. Dependency-free on
    purpose: pulling in html2text would reintroduce the exact class of
    upstream-drift problem this is fixing.
    """
    if not isinstance(value, str) or not value.strip():
        return None
    text = _TAG_RE.sub(" ", value)
    text = html_mod.unescape(text)
    text = _WS_RE.sub(" ", text).strip()
    return text or None
# -----------------------------------------------------------------------------

# --- Discipline classification (frozen v4) -----------------------------------
# Maps a job title to one of 25 disciplines (craft/training, not org unit).
# Ordered rules, first match wins: specific/technical craft is matched before
# broad seniority words; Engineering (engineer/architect) precedes the
# blue-collar buckets; two late catch-alls ("analyst" -> Data & Analytics,
# "specialist" -> Customer Success) only fire when nothing domain-specific hit.
# Re-run every load so rule changes self-heal existing rows on the next pull.

_DISCIPLINE_RULES = [
    ("Engineering", r"\b(engineer|engineering|architect|developer|\bsre\b|devops|firmware|technical lead|software|\bswe\b|penetration tester|propulsion analyst|thermal analyst)\b", None),
    ("Research", r"\b(research scientist|research engineer|researcher|applied scientist|research fellow|research intern|research lead|research manager|economist|ml researcher|ai researcher|machine learning researcher|postdoc|quantitative researcher|psychologist|fellows program|frontier agents intern)\b", None),
    ("Data & Analytics", r"\b(data analyst|business intelligence|bi analyst|analytics|data scientist|data science|business analyst|product analyst|digital analyst|insights|competitive intelligence|market intelligence|data quality)\b", None),
    ("Product Management", r"\b(product manager|product management|group product manager|director of product|product director|head of product|product owner|product lead)\b", None),
    ("Project/Program Management", r"\b(project manager|program manager|technical program|tpm|project lead|delivery manager|scrum master|scheduler|program director|special projects manager|project planner)\b", None),
    ("Design", r"\b(designer|design|\bux\b|\bui\b|user experience|creative director|creative lead|art director|motion graphics|graphic)\b", None),
    ("IT / Infrastructure", r"\b(data center|datacenter|it support|it network|it systems|systems administrator|network administrator|network infrastructure|help desk|helpdesk|it helpdesk|technology partner|desktop support|site reliability lead)\b", None),
    ("Security", r"\b(security analyst|security operator|security officer|soc analyst|threat|cyber|cybersecurity|information security|infosec|insider risk|physical security|security risk|incident response|security operations|comsec|security controls|security hardware|identity & access|iam\b)\b", None),
    ("Safety / EHS", r"\b(environmental health|health & safety|health and safety|\behs\b|industrial hygienist|safety specialist|specialist, safety|safety support|environmental specialist)\b", None),
    ("Quality / Inspection", r"\b(quality inspector|quality specialist|nde inspector|\bndt\b|\bnde\b|inspector|quality assurance|\bqa\b|precision inspector|welding inspector|quality control)\b", None),
    ("Skilled Trades", r"\b(welder|welding|machinist|\bcnc\b|\bedm\b|electrician|\bhvac\b|plumber|technician|mechanic|maintenance|fabricator|fabrication|tube bender|foreman|superintendent|journeyman|diamond turning|tool & die|tool and die|cmm programmer|driver)\b", r"data center technician|network|it support|it systems"),
    ("Manufacturing / Production", r"\b(production|manufacturing|assembly|build specialist|build supervisor|machine operator|operator|process operator|material handler|automation & controls|integration & test|integration specialist|test specialist|metrology|smt\b|receiving specialist|shipping specialist)\b", None),
    ("Supply Chain / Procurement", r"\b(sourcing|global supply|supply manager|supplier|buyer|procurement|inventory|materials management|purchasing|logistics|supply chain|warehouse|supply materials)\b", None),
    ("Hospitality / Facilities", r"\b(chef|cook|barista|porter|mixologist|food service|hospitality|facilities|janitor|custodian|soft services)\b", None),
    ("Sales", r"\b(sales|account executive|\bae\b|account manager|\bsdr\b|\bbdr\b|sales development|business development|revenue|go.?to.?market|\bgtm\b|partnerships|partner development|partner manager|partner lead|partner specialist|alliance|alliances|channel|account lead|account specialist|renewals|renewal manager|value advisor|relationship manager|market manager|growth lead|growth manager|growth specialist|enterprise\b|market access)\b", None),
    ("Marketing", r"\b(marketing|marketer|\bbrand\b|demand gen|demand generation|growth marketing|content|communications|\bcomms\b|social media|\bseo\b|\bsem\b|public relations|\bpr\b|copy|editor|events|campaign|paid media|analyst relations|web producer|photographer|technical writer)\b", None),
    ("Finance", r"\b(finance|financial|accounting|accountant|accounts payable|accounts receivable|controller|fp&a|treasury|audit|auditor|\btax\b|commissions|payroll|underwriter|underwriting|credit|collections|\bloan\b|mortgage|billing|capital markets|controllership|reporting|fraud|pricing|deal desk|deal pricing|investment|investments|liquidity|stock plan|stock administration|transfer pricing|lending)\b", None),
    ("Legal", r"\b(legal|counsel|attorney|paralegal|compliance|privacy|contracts manager|contract manager|contracts negotiator|sanctions|regulatory|immigration|trust & safety)\b", None),
    ("Strategy", r"\b(strategy|strategic|strategist|corporate development|corp dev|\bpolicy\b|government affairs|public policy|government incentives|land acquisition|site selection|real estate|construction manager|campus planning|site expansion)\b", None),
    ("Operations", r"\b(operations|\bops\b|bizops|biz ops|business operations|business process|resource manager|workforce planning|localization|professional services|practice manager)\b", None),
    ("Recruiting / People", r"\b(recruiter|recruiting|talent|\bpeople\b|human resources|\bhr\b|sourcer|benefits|compensation|employee relations|total rewards|candidate specialist|learning|generalist|mobility)\b", None),
    ("Customer Success", r"\b(customer success|customer support|technical account manager|\btam\b|implementation|onboarding|support specialist|consultant|solutions consultant|premium support|product support|client services|member service|escalation|escalations|enablement|delivery success|services solutions|technical solutions|solution specialist|technical delivery|deployment)\b", None),
    ("Administrative", r"\b(executive assistant|administrative|\badmin\b|office manager|receptionist|coordinator|assistant|briefing manager)\b", None),
    ("Data & Analytics", r"\banalyst\b", None),
    ("Customer Success", r"\bspecialist\b", None),
]

_DISCIPLINE_COMPILED = [
    (d, re.compile(p, re.I), re.compile(n, re.I) if n else None)
    for d, p, n in _DISCIPLINE_RULES
]


def classify_discipline(title):
    t = title or ""
    for discipline, pos, neg in _DISCIPLINE_COMPILED:
        if pos.search(t) and not (neg and neg.search(t)):
            return discipline
    return "Other"
# -----------------------------------------------------------------------------

# --- Role classification (Title_Role_Rules v4) -------------------------------
# Maps a job title to a base role archetype using ordered keyword rules,
# first match wins. Each rule has one or two keywords joined by an operator:
#   op == "AND"  -> every keyword must be present
#   op == "OR"   -> any keyword present (also used for single-keyword rules)
# Matching is whole-word and case-insensitive. Ordering matters: compound and
# specific rules sit above broad catch-alls (e.g. Marketing precedes bare
# Market; Program Manager precedes bare Program). Unmatched titles return None
# (stored as NULL) rather than being forced into a catch-all.
# Re-run every load so rule edits self-heal existing rows on the next pull.
#
# Source of truth: Title_Role_Rules_v4.xlsx, regenerated into this list via a
# Colab cell when rules change. Do not hand-edit individual rows here without
# updating the spreadsheet too.

ROLE_RULES = [
    {"order": 1, "role": 'Audit', "op": 'OR', "keywords": ['Audit', 'Auditor']},
    {"order": 2, "role": 'Chief of Staff', "op": None, "keywords": ['Chief of Staff']},
    {"order": 3, "role": 'executive assistant', "op": None, "keywords": ['executive assistant']},
    {"order": 4, "role": 'Account Executive', "op": 'OR', "keywords": ['Account Executive', 'Account Exec']},
    {"order": 5, "role": 'Account Manager', "op": 'OR', "keywords": ['Account Manager', 'Account Mgr']},
    {"order": 6, "role": 'Account Lead/Director', "op": 'OR', "keywords": ['Account Lead', 'Account Director']},
    {"order": 7, "role": 'Product Manager', "op": None, "keywords": ['Product Manager']},
    {"order": 8, "role": 'Program Manager', "op": None, "keywords": ['Program Manager']},
    {"order": 9, "role": 'Project Manager', "op": None, "keywords": ['Project Manager']},
    {"order": 10, "role": 'Relationship Manager', "op": None, "keywords": ['Relationship Manager']},
    {"order": 11, "role": 'Marketing Manager', "op": None, "keywords": ['Marketing Manager']},
    {"order": 12, "role": 'Engineering Manager', "op": None, "keywords": ['Engineering Manager']},
    {"order": 13, "role": 'Engineering Director', "op": None, "keywords": ['Engineering Director']},
    {"order": 14, "role": 'Solutions Architect', "op": None, "keywords": ['Solutions Architect']},
    {"order": 15, "role": 'Data Analyst/Analysis', "op": 'OR', "keywords": ['Data Analyst', 'Data Analysis']},
    {"order": 16, "role": 'Data Scientist/Science', "op": 'OR', "keywords": ['Data Scientist', 'Data Science']},
    {"order": 17, "role": 'operations manager', "op": None, "keywords": ['operations manager']},
    {"order": 18, "role": 'sales manager', "op": None, "keywords": ['sales manager']},
    {"order": 19, "role": 'supply manager', "op": None, "keywords": ['supply manager']},
    {"order": 20, "role": 'sales specialist', "op": None, "keywords": ['sales specialist']},
    {"order": 21, "role": 'sourcing manager', "op": None, "keywords": ['sourcing manager']},
    {"order": 22, "role": 'finance manager', "op": None, "keywords": ['finance manager']},
    {"order": 23, "role": 'operations associate', "op": None, "keywords": ['operations associate']},
    {"order": 24, "role": 'operations analyst', "op": None, "keywords": ['operations analyst']},
    {"order": 25, "role": 'Engineer', "op": None, "keywords": ['Engineer']},
    {"order": 26, "role": 'counsel', "op": None, "keywords": ['counsel']},
    {"order": 27, "role": 'Product Management', "op": None, "keywords": ['Product Management']},
    {"order": 28, "role": 'Finance & Strategy', "op": 'AND', "keywords": ['Finance', 'Strategy']},
    {"order": 29, "role": 'Strategy & Operations', "op": 'AND', "keywords": ['Strategy', 'Operations']},
    {"order": 30, "role": 'Auditor', "op": None, "keywords": ['Auditor']},
    {"order": 31, "role": 'Designer', "op": None, "keywords": ['Designer']},
    {"order": 32, "role": 'Technician', "op": None, "keywords": ['Technician']},
    {"order": 33, "role": 'Scientist', "op": 'OR', "keywords": ['Scientist', 'Science']},
    {"order": 34, "role": 'Recruiter', "op": 'OR', "keywords": ['Recruiter', 'Recruiting']},
    {"order": 35, "role": 'Architect', "op": None, "keywords": ['Architect']},
    {"order": 36, "role": 'Researcher', "op": None, "keywords": ['Researcher']},
    {"order": 37, "role": 'Accountant/Accounting', "op": 'OR', "keywords": ['Accountant', 'Accounting']},
    {"order": 38, "role": 'Mechanic', "op": None, "keywords": ['Mechanic']},
    {"order": 39, "role": 'Welder', "op": 'OR', "keywords": ['Welder', 'Welding']},
    {"order": 40, "role": 'Driver', "op": None, "keywords": ['Driver']},
    {"order": 41, "role": 'Inspector', "op": None, "keywords": ['Inspector']},
    {"order": 42, "role": 'Economist', "op": None, "keywords": ['Economist']},
    {"order": 43, "role": 'Cook', "op": 'OR', "keywords": ['Cook', 'Chef']},
    {"order": 44, "role": 'Machinist', "op": 'OR', "keywords": ['Machinist', 'Machine']},
    {"order": 45, "role": 'Trainer', "op": None, "keywords": ['Trainer']},
    {"order": 46, "role": 'Business Planner/Planning', "op": 'OR', "keywords": ['Business Planner', 'Business Planning']},
    {"order": 47, "role": 'Consultant', "op": None, "keywords": ['Consultant']},
    {"order": 48, "role": 'Strategist', "op": None, "keywords": ['Strategist']},
    {"order": 49, "role": 'Developer', "op": None, "keywords": ['Developer']},
    {"order": 50, "role": 'Administrator', "op": 'OR', "keywords": ['Admin', 'Administrator']},
    {"order": 51, "role": 'Legal & Counsel', "op": 'OR', "keywords": ['Counsel', 'Legal']},
    {"order": 52, "role": 'Product Strategy', "op": 'AND', "keywords": ['Product', 'Strategy']},
    {"order": 53, "role": 'Strategy', "op": None, "keywords": ['Strategy']},
    {"order": 54, "role": 'Engineering', "op": None, "keywords": ['Engineering']},
    {"order": 55, "role": 'Strategic Finance', "op": None, "keywords": ['Strategic Finance']},
    {"order": 56, "role": 'Corp Dev', "op": None, "keywords": ['Corporate Development']},
    {"order": 57, "role": 'Sales Dev', "op": None, "keywords": ['Sales Development']},
    {"order": 58, "role": 'Biz Dev', "op": None, "keywords": ['Business Development']},
    {"order": 59, "role": 'Customer Success', "op": None, "keywords": ['Customer Success']},
    {"order": 60, "role": 'Customer Support', "op": None, "keywords": ['Customer Support']},
    {"order": 61, "role": 'Marketing', "op": None, "keywords": ['Marketing']},
    {"order": 62, "role": 'Supply Chain', "op": None, "keywords": ['Supply Chain']},
    {"order": 63, "role": 'Delivery Success', "op": None, "keywords": ['Delivery Success']},
    {"order": 64, "role": 'Financial Planning', "op": None, "keywords": ['Financial Planning']},
    {"order": 65, "role": 'Sourcing', "op": None, "keywords": ['Sourcing']},
    {"order": 66, "role": 'Incident', "op": 'OR', "keywords": ['Incident', 'Escalations']},
    {"order": 67, "role": 'Production', "op": 'OR', "keywords": ['Production', 'Manufacturing']},
    {"order": 68, "role": 'Research', "op": None, "keywords": ['Research']},
    {"order": 69, "role": 'People', "op": None, "keywords": ['People']},
    {"order": 70, "role": 'Tax', "op": None, "keywords": ['Tax']},
    {"order": 71, "role": 'Fraud', "op": None, "keywords": ['Fraud']},
    {"order": 72, "role": 'Financing', "op": None, "keywords": ['Financing']},
    {"order": 73, "role": 'Treasury', "op": None, "keywords": ['Treasury']},
    {"order": 74, "role": 'Contract', "op": 'OR', "keywords": ['Contract', 'Contracts']},
    {"order": 75, "role": 'Technical', "op": None, "keywords": ['Technical']},
    {"order": 76, "role": 'Contract Job', "op": None, "keywords": ['(Contract)']},
    {"order": 77, "role": 'Alliance', "op": None, "keywords": ['Alliance']},
    {"order": 78, "role": 'Partnerships', "op": None, "keywords": ['Partnerships']},
    {"order": 79, "role": 'Engagement', "op": None, "keywords": ['Engagement']},
    {"order": 80, "role": 'Enablement', "op": None, "keywords": ['Enablement']},
    {"order": 81, "role": 'Market', "op": None, "keywords": ['Market']},
    {"order": 82, "role": 'Analytics (Other)', "op": None, "keywords": ['Analytics']},
    {"order": 83, "role": 'Finance (Other)', "op": None, "keywords": ['Finance']},
    {"order": 84, "role": 'Analyst (Other)', "op": None, "keywords": ['Analyst']},
    {"order": 85, "role": 'Sales (other)', "op": None, "keywords": ['Sales']},
    {"order": 86, "role": 'GTM (other)', "op": None, "keywords": ['GTM']},
    {"order": 87, "role": 'Operations (other)', "op": None, "keywords": ['Operations']},
    {"order": 88, "role": 'Support (Other)', "op": None, "keywords": ['Support']},
    {"order": 89, "role": 'Program (Other)', "op": None, "keywords": ['Program']},
    {"order": 90, "role": 'Planning (other)', "op": None, "keywords": ['Planning']},
    {"order": 91, "role": 'Design (Other)', "op": None, "keywords": ['Design']},
    {"order": 92, "role": 'Analysis (other)', "op": None, "keywords": ['Analysis']},
    {"order": 93, "role": 'Tech (other)', "op": None, "keywords": ['Tech']},
]

# Pre-compile each keyword to a whole-word, case-insensitive pattern once,
# preserving the intended first-match-wins order (by "order" field).
_ROLE_COMPILED = [
    {
        "role": r["role"],
        "op": r["op"],
        "patterns": [
            re.compile(r"\b" + re.escape(str(k).strip()) + r"\b", re.I)
            for k in r["keywords"]
        ],
    }
    for r in sorted(ROLE_RULES, key=lambda x: x["order"])
]


def classify_role(title):
    t = title or ""
    if not t:
        return None
    for rule in _ROLE_COMPILED:
        pats = rule["patterns"]
        if rule["op"] == "AND":
            hit = all(p.search(t) for p in pats)
        else:  # "OR" or single-keyword
            hit = any(p.search(t) for p in pats)
        if hit:
            return rule["role"]
    return None
# -----------------------------------------------------------------------------

# --- Level classification (frozen v1) ----------------------------------------
# Maps a job title to a seniority/level value, an axis independent of
# discipline and role. Ordered rules, first match wins. Each rule lists one or
# two patterns; multiple patterns must ALL match (AND, used for "Senior +
# word" combos so word order/adjacency doesn't matter). Titles are normalized
# (Sr./Sr/Snr/Snr. -> Senior) before classification, but the normalized string
# is only used for matching, never written back to the stored title. Unmatched
# titles return None (stored as NULL). Re-run every load so rule edits
# self-heal existing rows on the next pull.

_SENIOR_PATTERN = re.compile(r"\b(?:sr|snr)\.?\b", re.IGNORECASE)


def normalize_title_for_level(title):
    if not title:
        return title
    return _SENIOR_PATTERN.sub("Senior", title)


_LEVEL_RULES = [
    ("CXO",              [r"\bchief\b", r"\bofficer\b"]),
    ("VP",                [r"\b(vice\s+president|vp)\b"]),
    ("GM",                [r"\b(general\s+manager|gm)\b"]),
    ("Chief of Staff",    [r"\b(chief\s+of\s+staff|cos)\b"]),
    ("Supervisor",        [r"\bsupervisor\b"]),
    ("Superintendent",    [r"\bsuperintendent\b"]),
    ("Senior Director",   [r"\bsenior\b", r"\bdirector\b"]),
    ("Director",          [r"\b(director|dir\.?)\b"]),
    ("Head of",           [r"\bhead\s+of\b"]),
    ("Senior Principal",  [r"\bsenior\b", r"\bprincipal\b"]),
    ("Principal",         [r"\bprincipal\b"]),
    ("Staff",             [r"\bstaff\b"]),
    ("Lead",              [r"\blead\b"]),
    ("Senior Manager",    [r"\bsenior\b", r"\bmanager\b"]),
    ("Manager",           [r"\b(manager|mgr\.?)\b"]),
    ("Senior Analyst",    [r"\bsenior\b", r"\banalyst\b"]),
    ("Analyst",           [r"\banalyst\b"]),
    ("Senior Associate",  [r"\bsenior\b", r"\bassociate\b"]),
    ("Associate",         [r"\bassociate\b"]),
    ("Specialist",        [r"\bspecialist\b"]),
    ("Coordinator",       [r"\bcoordinator\b"]),
    ("Assistant",         [r"\bassistant\b"]),
    ("Rotation",          [r"\brotation\b"]),
    ("I",                 [r"\bI\b"]),
    ("II",                [r"\bII\b"]),
    ("Senior",            [r"\bsenior\b"]),  # catch-all, must stay last
]
_LEVEL_CASE_SENSITIVE = {"I", "II"}

_LEVEL_COMPILED = [
    (
        name,
        [re.compile(p, 0 if name in _LEVEL_CASE_SENSITIVE else re.IGNORECASE) for p in patterns],
    )
    for name, patterns in _LEVEL_RULES
]


def classify_level(title):
    t = normalize_title_for_level(title)
    if not t:
        return None
    for name, patterns in _LEVEL_COMPILED:
        if all(p.search(t) for p in patterns):
            return name
    return None
# -----------------------------------------------------------------------------

snapshot_date = datetime.now(timezone.utc).date().isoformat()

FACT_COLS = ["snapshot_date", "watchlist_company", "ats_id", "ats_type", "title", "location",
             "is_remote", "department", "team", "employment_type", "salary_min", "salary_max",
             "salary_currency", "posted_at", "fetched_at", "url", "apply_url",
             "description_hash", "hash_algo"]
DIM_COLS = ["watchlist_company", "ats_id", "title", "location", "department", "description",
            "url", "apply_url", "last_seen", "fetched_at", "discipline", "role_keyword",
            "level", "raw", "description_change_count",
            "description_last_change_chars", "description_plain_len", "requisition_id"]

# description_last_change is not tracked here: it duplicated the existing
# current_version_first_seen column (verified byte-identical), which
# refresh_job_freshness() already maintains after every run. Consolidated
# onto that column; the jobs_location_flags view aliases it back to the
# description_last_change name for existing consumers.
CHANGE_STATE_COLS = ["watchlist_company", "ats_id", "current_description_hash",
                      "hash_algo", "description_change_count",
                      "description_last_change_chars", "description_plain_len"]


def load_watchlist():
    """Read active companies from the watchlist_companies table.

    scraper_kwargs is an optional JSONB column for scrapers that need more
    than a bare company_slug (e.g. Eightfold tenants on a custom domain like
    Microsoft, which needs base_url and domain). NULL/empty for every company
    on a default slug-based setup, so this is a no-op for the existing rows.
    """
    resp = sb.table("watchlist_companies") \
        .select("company,ats,slug,scraper_kwargs") \
        .eq("active", True) \
        .order("priority") \
        .execute()
    rows = resp.data or []
    watchlist = [
        {
            "company": r["company"],
            "ats": (r["ats"] or "").lower(),
            "slug": r["slug"],
            "scraper_kwargs": r.get("scraper_kwargs") or {},
        }
        for r in rows
    ]
    if not watchlist:
        print("ERROR: watchlist read returned 0 active companies; aborting "
              "(check the watchlist_companies table and DB connectivity).")
        sys.exit(1)
    return watchlist


def load_change_tracking_state():
    """Bulk pre-read of job_content's change-tracking columns, keyed by
    (watchlist_company, ats_id), so the per-job loop below can tell a real
    description edit from a scraper's null-hash blip without re-deriving
    history from raw_watchlist_jobs (which is pruned to RETENTION_DAYS).

    current_description_hash is job_content's existing "previous hash"
    column, already kept in sync by the refresh_job_freshness RPC after
    every run (it only updates when the day's hash is both present and
    different). Reusing it here avoids tracking the same hash twice.
    hash_algo travels alongside it so the comparison below can tell a
    hashing-algorithm change apart from a real content change.

    Paginated in chunks of 1000, PostgREST's default max rows per request.
    A short final page ends the read; anything else raises rather than
    proceeding on a partial read, since these columns are written back on
    every row of every run (added to DIM_COLS) -- a partial pre-read would
    silently reset the rest of job_content's change-tracking state to
    0/null on the next upsert, with no error surfaced.
    """
    state = {}
    page_size = 1000
    offset = 0
    while True:
        resp = sb.table("job_content").select(",".join(CHANGE_STATE_COLS)) \
            .order("watchlist_company").order("ats_id") \
            .range(offset, offset + page_size - 1).execute()
        rows = resp.data or []
        for r in rows:
            state[(r["watchlist_company"], r["ats_id"])] = r
        if len(rows) < page_size:
            break
        offset += page_size

    expected = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    if len(state) != expected:
        print(f"ERROR: change-tracking pre-read got {len(state)} rows but "
              f"job_content has {expected}; aborting before write to avoid "
              f"resetting change-tracking state for the difference.")
        sys.exit(1)
    return state


def main():
    watchlist = load_watchlist()
    print(f"Loaded {len(watchlist)} active companies from watchlist_companies")

    change_state = load_change_tracking_state()
    print(f"Pre-read change-tracking state for {len(change_state)} jobs")

    fact_rows, dim_rows = [], []
    failures = []

    for entry in watchlist:
        company, ats, slug = entry["company"], entry["ats"], entry["slug"]
        scraper_kwargs = entry.get("scraper_kwargs") or {}
        if ats not in SCRAPERS:
            print(f"SKIP {company:12s}: unknown ats '{ats}' (no scraper)")
            failures.append(company)
            continue
        try:
            jobs = SCRAPERS[ats](slug, **scraper_kwargs).fetch()

            for j in jobs:
                d = j.model_dump(mode="json")
                d["snapshot_date"] = snapshot_date
                d["watchlist_company"] = company
                d["ats_id"] = str(d.get("ats_id"))
                d["last_seen"] = snapshot_date

                # Hash a normalized plain-text projection of the description
                # (see description_fingerprint above), not the raw field --
                # ats-scrapers decides the raw shape, and that shape already
                # changed once across a version bump.
                raw_description = d.get("description")
                fingerprint = description_fingerprint(raw_description)
                new_hash = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest() if fingerprint else None
                d["description_hash"] = new_hash
                d["hash_algo"] = HASH_ALGO

                # Char-delta change tracking, computed on the fingerprint
                # length rather than the raw stored description's length, so
                # HTML markup weight never registers as a content change.
                # new_hash/new_len are None together whenever today's
                # description came back empty (a scraper miss, e.g.
                # Microsoft's Eightfold capture flakes on ~80% of days) --
                # require new_hash is not None, not just prev_hash, or every
                # such miss would register as a "change" against the last
                # real hash.
                #
                # Algo-aware: if prev_algo doesn't match this run's HASH_ALGO
                # (including every pre-migration row, where hash_algo is
                # still NULL), prev_hash was computed by a different
                # normalizer -- a mismatch there reflects the algorithm
                # switch, not necessarily a content edit, so it must not
                # register as a change. refresh_job_freshness applies the
                # same rule to current_version_first_seen. This is what lets
                # a future algorithm change self-heal on its own next run,
                # with no cutover-night script. Accepted limitation: a
                # genuine content edit landing on the exact same run as an
                # algorithm switch is indistinguishable from the switch
                # itself and gets swallowed -- one run's blind spot, not
                # ongoing.
                new_len = len(fingerprint) if fingerprint else None
                prev = change_state.get((company, d["ats_id"]))
                prev_hash = prev["current_description_hash"] if prev else None
                prev_algo = prev.get("hash_algo") if prev else None

                if prev is None:
                    change_count, last_chars = 0, None
                elif prev_algo != HASH_ALGO:
                    change_count = prev["description_change_count"] or 0
                    last_chars = prev["description_last_change_chars"]
                elif prev_hash is not None and new_hash is not None and new_hash != prev_hash:
                    change_count = (prev["description_change_count"] or 0) + 1
                    prev_len = prev["description_plain_len"]
                    last_chars = (new_len - prev_len) if (new_len is not None and prev_len is not None) else None
                else:
                    change_count = prev["description_change_count"] or 0
                    last_chars = prev["description_last_change_chars"]

                d["description_change_count"] = change_count
                d["description_last_change_chars"] = last_chars
                # Only refresh the length helper when today's text is
                # real; on a null-hash day, keep the last known length
                # so the next real change can still compute a delta.
                d["description_plain_len"] = (
                    new_len if new_len is not None
                    else (prev["description_plain_len"] if prev else None)
                )

                # d["description"] is already what ats-scrapers returned
                # (HTML for Greenhouse, HTML-preferred for Ashby, etc.) --
                # storage-ready natively, no second fetch or html_map merge
                # needed.

                # Classify discipline from title (frozen v4 rules).
                d["discipline"] = classify_discipline(d.get("title"))

                # Classify role archetype from title (Title_Role_Rules v4).
                d["role_keyword"] = classify_role(d.get("title"))

                # Classify seniority level from title (frozen v1 rules).
                d["level"] = classify_level(d.get("title"))

                fact_rows.append({k: d.get(k) for k in FACT_COLS})
                dim_rows.append({k: d.get(k) for k in DIM_COLS})

            print(f"OK   {company:12s} ({ats}/{slug}): {len(jobs)} jobs")
        except Exception as e:
            print(f"FAIL {company:12s} ({ats}/{slug}): {type(e).__name__}: {e}")
            failures.append(company)

    def dedupe(rows, keys):
        seen = {}
        for r in rows:
            seen[tuple(r[k] for k in keys)] = r
        return list(seen.values())

    fact_rows = dedupe(fact_rows, ["snapshot_date", "watchlist_company", "ats_id"])
    dim_rows = dedupe(dim_rows, ["watchlist_company", "ats_id"])
    print(f"Prepared {len(fact_rows)} fact rows, {len(dim_rows)} dimension rows")

    if not fact_rows:
        print("ERROR: no rows pulled from any company; aborting before write.")
        sys.exit(1)

    def upsert_chunked(table, rows, conflict, size=500):
        for i in range(0, len(rows), size):
            sb.table(table).upsert(rows[i:i + size], on_conflict=conflict).execute()
            print(f"  {table}: upserted {min(i + size, len(rows))}/{len(rows)}")

    print("Writing fact table...")
    upsert_chunked("raw_watchlist_jobs", fact_rows, "snapshot_date,watchlist_company,ats_id")
    print("Writing job dimension...")
    upsert_chunked("job_content", dim_rows, "watchlist_company,ats_id")

    print("Refreshing freshness columns...")
    sb.rpc("refresh_job_freshness", {"run_date": snapshot_date}).execute()
    print("  refresh_job_freshness done")

    print("Refreshing location flags...")
    sb.rpc("refresh_location_flags").execute()
    print("  refresh_location_flags done")

    print("Clearing descriptions for non-Seattle jobs...")
    sb.rpc("null_non_seattle_description").execute()
    print("  done")

    print("Clearing raw backup data for non-Seattle jobs...")
    sb.rpc("null_non_seattle_raw").execute()
    print("  done")

    print("Pruning old raw snapshots...")
    RETENTION_DAYS = 14
    cutoff_date = (datetime.now(timezone.utc).date() - timedelta(days=RETENTION_DAYS)).isoformat()
    sb.table("raw_watchlist_jobs").delete().lt("snapshot_date", cutoff_date).execute()
    print(f"  raw_watchlist_jobs: pruned snapshots older than {cutoff_date}")

    fact_count = sb.table("raw_watchlist_jobs").select("ats_id", count="exact") \
        .eq("snapshot_date", snapshot_date).limit(1).execute().count
    dim_count = sb.table("job_content").select("ats_id", count="exact").limit(1).execute().count
    print(f"Verification: {fact_count} fact rows for {snapshot_date}, {dim_count} rows in job_content")

    if failures:
        print(f"ERROR: pulls failed for: {failures}")
        sys.exit(1)


if __name__ == "__main__":
    main()
