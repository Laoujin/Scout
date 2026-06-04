#!/usr/bin/env python3
"""Atlas research triage — scan atlas/research/ for broken, flagged, or incomplete expeditions.

Walks every research folder, reads frontmatter + manifest.json + .scout-result.json,
and classifies each node. Detection only — no edits, no git. The skill's playbook
(SKILL.md) decides remediation per finding.

Usage:
  scan.py [ATLAS_RESEARCH_DIR]   # default: ./atlas/research, else $ATLAS_DIR/research
  scan.py --json                 # machine-readable findings array

Why a script and not pure grep: the parent/leaf distinction, body-size threshold,
and manifest/frontmatter cross-checks need real parsing, not a regex.
"""
import json
import os
import re
import sys
from pathlib import Path

# Body shorter than this (chars, after frontmatter) with a failure marker = genuine
# failure (content is gone). Calibrated against "Research failed: child run.sh exit 1".
GENUINE_FAILURE_MAX_BODY = 200
# A node carrying a failure status but a body longer than this almost certainly has
# real content the flag is hiding — a FALSE flag to clean, not a genuine failure.
REAL_CONTENT_MIN_BODY = 600
FAILURE_STATUSES = {"failed", "error", "error_with_content"}
FAILURE_MARKERS = ("research failed", "run.sh exit")

SEVERITY = {  # ordering for the grouped report
    "DEAD": 0, "GENUINE_FAILURE": 1, "STRAY_DIR": 2, "FALSE_FLAG": 3,
    "MANIFEST_MISMATCH": 4, "MISSING_COST": 5, "MISSING_COVER": 6,
    "MISSING_MODEL": 7, "MISSING_DURATION": 8, "MISSING_ISSUE": 9,
    "SLUG_DOUBLED_DATE": 10, "SLUG_REPEAT_TOKEN": 11, "LEDGER_MISMATCH": 12,
}

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})")
DOUBLED_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-\1\b")
STOPWORDS = {"the", "and", "for", "with", "near", "weekend", "michelin", "dinner",
             "anchored", "around", "within", "star", "stars", "plan", "from"}


def split_frontmatter(text):
    """Return (frontmatter_text, body) splitting on the first two '---' fences."""
    if not text.startswith("---"):
        return "", text
    parts = text.split("\n")
    if parts[0].strip() != "---":
        return "", text
    for i in range(1, len(parts)):
        if parts[i].strip() == "---":
            return "\n".join(parts[1:i]), "\n".join(parts[i + 1:])
    return "", text  # no closing fence


def parse_scalars(fm):
    """Top-level `key: value` scalars only. Nested block keys (children:) map to ''. """
    d = {}
    for line in fm.split("\n"):
        m = re.match(r"^([a-zA-Z_][\w]*):\s?(.*)$", line)
        if m:
            d[m.group(1)] = m.group(2).strip()
    return d


def read_node(folder):
    """Read a research folder's index.{md,html}. Returns dict or None if no index."""
    for ext in ("md", "html"):
        p = folder / f"index.{ext}"
        if p.exists():
            text = p.read_text(encoding="utf-8", errors="replace")
            fm, body = split_frontmatter(text)
            return {
                "path": p, "folder": folder, "fm_text": fm,
                "scalars": parse_scalars(fm), "body": body.strip(),
                "has_children_block": bool(re.search(r"^children:", fm, re.M)),
            }
    return None


def child_dirs(folder):
    return [d for d in sorted(folder.iterdir())
            if d.is_dir() and not d.name.startswith(".") and d.name != "views"]


def load_result_cost(folder):
    p = folder / ".scout-result.json"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace")).get("total_cost_usd")
    except Exception:
        return None


def slug_repeat_token(slug):
    """Detect the Place-Region-Place doubling signature (e.g. `taichung-taiwan-taichung`):
    a token repeated exactly two positions apart. Plain re-use of a word elsewhere in a
    slug (a town named like its restaurant, `deep research` vs `research agents`) is NOT
    flagged — that gap-of-1 adjacency is what the slug-doubling bug actually produces."""
    toks = slug.split("-")
    return sorted({toks[i] for i in range(len(toks) - 2)
                   if toks[i] == toks[i + 2] and len(toks[i]) >= 4
                   and toks[i] not in STOPWORDS and not toks[i].isdigit()})


def add(findings, cat, path, detail):
    findings.append({"category": cat, "path": str(path), "detail": detail})


def check_node(node, findings, *, is_parent, slug):
    sc = node["scalars"]
    folder, body = node["folder"], node["body"]
    body_lc = body.lower()
    status = sc.get("status", "").strip().strip('"').lower()
    has_failure_marker = any(m in body_lc for m in FAILURE_MARKERS)
    tiny = len(body) < GENUINE_FAILURE_MAX_BODY
    real = len(body) >= REAL_CONTENT_MIN_BODY

    # Genuine failure vs false flag: same status, different body reality.
    if (status in FAILURE_STATUSES or has_failure_marker) and tiny:
        add(findings, "GENUINE_FAILURE", folder, "tiny body + failure marker — content gone, re-run to recover")
    elif (status in FAILURE_STATUSES or "validation_error" in sc) and real:
        why = "validation_error present" if "validation_error" in sc else f"status={status}"
        add(findings, "FALSE_FLAG", folder, f"{why} but body has real content ({len(body)} chars) — strip flag, set status success")

    # Cover: an orphaned file, a dangling reference, or no cover at all on a real page.
    cover_file = (folder / "cover.svg").exists()
    cover_line = "cover" in sc
    if cover_file and not cover_line:
        add(findings, "MISSING_COVER", folder, "cover.svg on disk but no `cover:` in frontmatter")
    elif cover_line and not cover_file:
        add(findings, "MISSING_COVER", folder, "`cover:` in frontmatter but no cover.svg on disk — dangling reference")
    elif not cover_file and not tiny:
        add(findings, "MISSING_COVER", folder, "no cover.svg and no `cover:` — never illustrated (or illustrator skipped)")

    # Every real research page (parent or leaf) should record what produced it.
    if not tiny:
        if "model" not in sc:
            add(findings, "MISSING_MODEL", folder, "no `model:` — which model produced this is unrecorded")
        if "duration_sec" not in sc:
            add(findings, "MISSING_DURATION", folder, "no `duration_sec:` — runtime unrecorded")

    # Per-leaf conventions. Interactive (subscription) runs carry cost_usd: "sub" and
    # legitimately have no issue number, so they're exempt from MISSING_ISSUE.
    is_sub_run = sc.get("cost_usd", "").strip().strip('"').lower() == "sub"
    if not is_parent and not tiny:
        if "cost_usd" not in sc:
            backfill = load_result_cost(folder)
            note = f"backfillable from .scout-result.json (${backfill})" if backfill else "lost (no result JSON)"
            add(findings, "MISSING_COST", folder, f"no `cost_usd` — {note}")
        if "issue" not in sc and not is_sub_run:
            add(findings, "MISSING_ISSUE", folder, "no `issue:` field")


def check_parent_structure(folder, node, findings):
    """manifest.json ↔ children dirs ↔ children: block consistency, dead-expedition detection."""
    subdirs = [d for d in child_dirs(folder) if read_node(d)]
    manifest = folder / "manifest.json"
    statuses = []
    if manifest.exists():
        try:
            entries = json.loads(manifest.read_text(encoding="utf-8", errors="replace"))
            statuses = [e.get("status", "") for e in entries]
            if len(entries) != len(subdirs):
                add(findings, "MANIFEST_MISMATCH", folder,
                    f"manifest lists {len(entries)} children, {len(subdirs)} child dirs on disk")
        except Exception as e:
            add(findings, "MANIFEST_MISMATCH", folder, f"manifest.json unreadable: {e}")
    # Dead expedition: every child failed AND parent has no real synthesis body.
    if statuses and all(s in FAILURE_STATUSES for s in statuses) and len(node["body"]) < REAL_CONTENT_MIN_BODY:
        add(findings, "DEAD", folder, f"all {len(statuses)} children failed, no synthesis survivor — delete or re-run")


def check_ledger(node, findings, *, is_parent):
    folder, sc = node["folder"], node["scalars"]
    ledger = folder / "citations.jsonl"
    if not ledger.exists():
        return
    lines = [l for l in ledger.read_text(encoding="utf-8", errors="replace").splitlines() if l.strip()]
    actual = len(lines)
    # Count shortfall = lost/truncated citations. Leaf nodes only: a PARENT's frontmatter
    # `citations` aggregates its children, while its own ledger holds just synthesis-level
    # cites — comparing the two is meaningless. More lines than declared is always benign:
    # Scout tolerates repeated URLs (skills/scout/SKILL.md rule 9) and authors round counts.
    if not is_parent and "citations" in sc:
        try:
            declared = int(sc["citations"])
            if declared - actual > max(3, declared // 10):
                add(findings, "LEDGER_MISMATCH", folder, f"frontmatter citations={declared} but only {actual} ledger lines — citations lost")
        except ValueError:
            pass
    # Integrity errors apply to every ledger, parent or leaf.
    for i, l in enumerate(lines, 1):
        try:
            if not json.loads(l).get("url", "").strip():
                add(findings, "LEDGER_MISMATCH", folder, f"ledger line {i} has empty url")
        except Exception:
            add(findings, "LEDGER_MISMATCH", folder, f"ledger line {i} is not valid JSON")


def scan(root):
    findings = []
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        slug = folder.name
        if DOUBLED_DATE_RE.match(slug):
            add(findings, "SLUG_DOUBLED_DATE", folder, "slug repeats its date prefix — duplicate/early-failed run")
        for tok in slug_repeat_token(slug):
            add(findings, "SLUG_REPEAT_TOKEN", folder, f"token '{tok}' repeats in slug — possible doubled name")

        node = read_node(folder)
        kids = [d for d in child_dirs(folder) if read_node(d)]
        empty_kids = [d for d in child_dirs(folder) if not read_node(d)]
        if node is None:
            if not kids:
                add(findings, "STRAY_DIR", folder, "no index.* and no valid children — stray/placeholder dir")
            continue
        is_parent = node["has_children_block"] or (folder / "manifest.json").exists() or bool(kids)

        check_node(node, findings, is_parent=is_parent, slug=slug)
        check_ledger(node, findings, is_parent=is_parent)
        if is_parent:
            check_parent_structure(folder, node, findings)
            for kid in kids:
                kn = read_node(kid)
                check_node(kn, findings, is_parent=False, slug=slug)
                check_ledger(kn, findings, is_parent=False)
            for ek in empty_kids:
                add(findings, "STRAY_DIR", ek, "child dir with no index.* — stray/placeholder")
    return findings


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv[1:]
    if args:
        root = Path(args[0])
    else:
        env = os.environ.get("ATLAS_DIR")
        root = Path(env) / "research" if env else Path("atlas/research")
    if not root.is_dir():
        sys.exit(f"not a directory: {root}  (pass atlas/research path as arg or set ATLAS_DIR)")

    findings = scan(root)
    findings.sort(key=lambda f: (SEVERITY.get(f["category"], 99), f["path"]))

    if as_json:
        print(json.dumps(findings, indent=2))
        return

    if not findings:
        print(f"clean — no triage findings under {root}")
        return
    by_cat = {}
    for f in findings:
        by_cat.setdefault(f["category"], []).append(f)
    rel = lambda p: os.path.relpath(p, root)
    print(f"# Atlas triage scan — {len(findings)} findings under {root}\n")
    for cat in sorted(by_cat, key=lambda c: SEVERITY.get(c, 99)):
        items = by_cat[cat]
        print(f"## {cat}  ({len(items)})")
        for f in items:
            print(f"  {rel(f['path'])}\n      → {f['detail']}")
        print()
    counts = "  ".join(f"{c}={len(by_cat[c])}" for c in sorted(by_cat, key=lambda c: SEVERITY.get(c, 99)))
    print(f"summary: {counts}")


if __name__ == "__main__":
    main()
