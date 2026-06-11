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
from datetime import datetime, timezone
from pathlib import Path

try:  # dimension check degrades to size-only when Pillow is absent
    from PIL import Image
    HAVE_PIL = True
except Exception:
    HAVE_PIL = False

# View images are web assets: shrunk to <=1600px WebP at authoring time
# (scout-view-author) and bulk-backfilled by atlas/scripts/optimize-images.py.
# Anything heavier is publish bloat — Atlas rebuilds the whole site per push and
# GitHub Pages caps the published site at 1 GB.
MAX_IMG_EDGE = 1600          # longest side, px
MAX_IMG_BYTES = 500 * 1024   # 500 KB
IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".gif")
# image path inside a quote/paren (html src="", css url(), markdown ](...))
IMG_REF_RE = re.compile(r"""['"(]\s*([\w][\w./-]*?\.(?:jpe?g|png|webp|gif))""", re.IGNORECASE)

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
    "SERIES_MISSING_ENTRY": 2, "IMAGE_MISSING": 2, "IMAGE_OVERSIZED": 13, "IMAGE_ORPHAN": 14,
}

# Critical = the research is actually broken (delete / re-run / repair). Everything
# else is hygiene (cosmetic metadata gaps) — kept off the homepage pill so a backlog
# of legacy metadata gaps can't drown the "X is broken" signal.
CRITICAL = {"DEAD", "GENUINE_FAILURE", "STRAY_DIR", "MANIFEST_MISMATCH",
            "LEDGER_MISMATCH", "FALSE_FLAG", "SERIES_MISSING_ENTRY", "IMAGE_MISSING"}


def severity_of(category):
    return "critical" if category in CRITICAL else "hygiene"

DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})")
DOUBLED_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-\1\b")
STOPWORDS = {"the", "and", "for", "with", "near", "weekend", "michelin", "dinner",
             "anchored", "around", "within", "star", "stars", "plan", "from"}


def split_frontmatter(text):
    """Return (frontmatter_text, body) splitting on the first two '---' fences.

    Tolerates a leading banner before the opening fence — blank lines and/or
    single-line HTML comments (html fragments carry a `<!-- format=html ... -->`
    line on top), so their frontmatter is still parsed rather than treated as
    absent (which would falsely flag every field as missing)."""
    parts = text.split("\n")
    start = 0
    while start < len(parts):
        s = parts[start].strip()
        if s == "" or (s.startswith("<!--") and s.endswith("-->")):
            start += 1
            continue
        break
    if start >= len(parts) or parts[start].strip() != "---":
        return "", text
    for i in range(start + 1, len(parts)):
        if parts[i].strip() == "---":
            return "\n".join(parts[start + 1:i]), "\n".join(parts[i + 1:])
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
    findings.append({"category": cat, "severity": severity_of(cat),
                     "path": str(path), "detail": detail})


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


# Series entries are bare list items (`- <slug>`); the mapping items they sit beside
# (`- slug:`, `- label:`) carry a `key: value`, so the colon distinguishes them.
SERIES_SLUG_RE = re.compile(r"^- slug:\s*(\S+)")
SERIES_ENTRY_RE = re.compile(r"^\s+-\s+(?!\S+:\s)(\S.*?)\s*$")


def check_series(root, findings):
    """Every entry in _data/series.yml must have a research/ folder. A dangling entry
    is a broken /series/<slug>/ card and a dead link — critical, not cosmetic. This is
    the cross-check scan() would otherwise miss (it only walks folders that exist)."""
    series_yml = root.parent / "_data" / "series.yml"
    if not series_yml.exists():
        return
    current = None
    for line in series_yml.read_text(encoding="utf-8", errors="replace").split("\n"):
        m = SERIES_SLUG_RE.match(line)
        if m:
            current = m.group(1)
            continue
        m = SERIES_ENTRY_RE.match(line)
        if m and not (root / m.group(1)).is_dir():
            add(findings, "SERIES_MISSING_ENTRY", root / m.group(1),
                f"listed in series '{current}' but research/{m.group(1)}/ does not exist")


def image_dims(path):
    """(w, h) or None when Pillow is unavailable / the file is unreadable."""
    if not HAVE_PIL:
        return None
    try:
        with Image.open(path) as im:
            return im.size
    except Exception:
        return None


def check_images(folder, findings):
    """Per-expedition image checks (one rglob covers child views too):
      IMAGE_MISSING  — a view references a local image that isn't on disk (broken <img>)
      IMAGE_ORPHAN   — an image on disk that no view references (dead build weight)
      IMAGE_OVERSIZED— an image past the WebP/size budget (publish bloat)."""
    used = set()
    missing = set()  # (view_file, ref) — dedup repeats within a file
    for tf in folder.rglob("*"):
        if not tf.is_file() or tf.suffix.lower() not in (".html", ".md", ".json"):
            continue
        text = tf.read_text(encoding="utf-8", errors="replace")
        for m in IMG_REF_RE.finditer(text):
            ref = m.group(1)
            if "://" in ref:  # absolute/remote — not a local asset
                continue
            try:
                target = (tf.parent / ref).resolve()
            except OSError:
                continue
            used.add(target)
            if not target.exists():
                missing.add((tf, ref))
    for tf, ref in sorted(missing, key=lambda x: (str(x[0]), x[1])):
        add(findings, "IMAGE_MISSING", tf, f"references '{ref}' but that file is not on disk — broken image")

    for img in folder.rglob("*"):
        if not img.is_file() or img.suffix.lower() not in IMAGE_EXTS:
            continue
        if img.resolve() not in used:
            add(findings, "IMAGE_ORPHAN", img, "on disk but referenced by no view — dead weight in the build")
        problems = []
        dims = image_dims(img)
        over_edge = bool(dims and max(dims) > MAX_IMG_EDGE)
        if over_edge:
            problems.append(f"{dims[0]}×{dims[1]}px (>{MAX_IMG_EDGE})")
        size = img.stat().st_size
        if size > MAX_IMG_BYTES:
            problems.append(f"{size // 1024}KB (>{MAX_IMG_BYTES // 1024}KB)")
        if problems:
            # Resizing only helps when the image is actually too big on its longest
            # edge. An in-bounds image that's merely heavy needs re-compression, not
            # a resize — only say "already ≤1600px" when dims are known and within budget.
            if not over_edge and dims:
                remedy = f"already ≤{MAX_IMG_EDGE}px — re-compress at lower quality"
            else:
                remedy = f"re-encode to WebP ≤{MAX_IMG_EDGE}px"
            add(findings, "IMAGE_OVERSIZED", img, "; ".join(problems) + " — " + remedy)


def scan(root):
    findings = []
    check_series(root, findings)
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        slug = folder.name
        if DOUBLED_DATE_RE.match(slug):
            add(findings, "SLUG_DOUBLED_DATE", folder, "slug repeats its date prefix — duplicate/early-failed run")
        for tok in slug_repeat_token(slug):
            add(findings, "SLUG_REPEAT_TOKEN", folder, f"token '{tok}' repeats in slug — possible doubled name")
        check_images(folder, findings)

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


def _utcnow_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def build_health(findings, root, generated):
    """Group findings by research slug, split by severity, for Atlas's _data/health.json.
    A research appears under `critical` if it has any critical finding (listing only its
    critical findings) and/or under `hygiene` for its hygiene findings — same research can
    appear in both. `counts` is the number of distinct research per tier (drives the pill)."""
    tree = {}  # slug -> severity -> (node, rel_path) -> [ {category, detail} ]
    for f in findings:
        p = Path(f["path"])
        try:
            rel = p.relative_to(root)
        except ValueError:
            rel = Path(p.name)
        parts = rel.parts
        slug = parts[0] if parts else p.name
        node = "parent" if len(parts) <= 1 else "child"
        (tree.setdefault(slug, {}).setdefault(f["severity"], {})
            .setdefault((node, str(rel)), []).append(
                {"category": f["category"], "detail": f["detail"]}))

    def bucket(sev):
        out = []
        for slug in sorted(tree):
            paths = tree[slug].get(sev)
            if not paths:
                continue
            items = [{"node": n, "path": pth, "findings": fs}
                     for (n, pth), fs in sorted(paths.items(), key=lambda kv: kv[0][1])]
            out.append({"slug": slug, "items": items})
        return out

    crit, hyg = bucket("critical"), bucket("hygiene")
    return {"generated": generated,
            "counts": {"critical": len(crit), "hygiene": len(hyg)},
            "critical": crit, "hygiene": hyg}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv[1:]
    as_health = "--health" in sys.argv[1:]
    if args:
        root = Path(args[0])
    else:
        env = os.environ.get("ATLAS_DIR")
        root = Path(env) / "research" if env else Path("atlas/research")
    if not root.is_dir():
        sys.exit(f"not a directory: {root}  (pass atlas/research path as arg or set ATLAS_DIR)")

    findings = scan(root)
    findings.sort(key=lambda f: (SEVERITY.get(f["category"], 99), f["path"]))

    if as_health:
        generated = os.environ.get("SCOUT_HEALTH_GENERATED") or _utcnow_iso()
        print(json.dumps(build_health(findings, root, generated), indent=2))
        return

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
