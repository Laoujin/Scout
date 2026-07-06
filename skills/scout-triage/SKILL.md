---
name: scout-triage
description: Use when auditing a published Atlas for broken, missing, or wrongly-flagged research — failed/empty expeditions, false ⚠ "degraded" badges, missing cost/cover/issue, doubled-date or duplicate-name slugs, manifest/ledger drift. Run periodically or after a batch of expeditions to find what went wrong.
user-invocable: false
disable-model-invocation: true
---

# Scout triage — auditing Atlas research health

## Overview

Scout's pipeline can leave damage on Atlas that the site renders silently: a perfectly-good page wearing a false failure flag, a dead expedition with no survivor, a child page missing from its parent's manifest, a backfillable-but-blank cost footer. This skill **sweeps `atlas/research/`, classifies every finding, then drives remediation** — page by page, with judgment, not blind fixes.

Detection is mechanical (`scan.py`); remediation is judgment (is this flagged page real content or a genuine failure?) and stays with you.

## When to use

- After a batch of expeditions fires (e.g. a michelin-weekend series) — catch failures before they pile up.
- Periodically, as a health check ("is anything missing or broken?").
- When the Atlas index shows a ⚠ badge, an empty Cost/Duration footer, or a card with no cover.
- When you suspect a Scout regression — a category that should be extinct (false flags, dup-URL aborts) reappearing means a code fix regressed.

## Step 1 — run the scan (detection)

```bash
python3 scout/skills/scout-triage/scan.py atlas/research      # or: ATLAS_DIR=... scan.py
python3 scout/skills/scout-triage/scan.py atlas/research --json   # machine-readable
```

Read-only. Groups findings by category, most-severe first, with a one-line `summary:` count. A clean tree prints `clean — no triage findings`.

## Step 2 — triage each category

| Category | Signal | Remediation |
|----------------------|----------------------------------------------------|-----------------------------------------------------------------|
| `DEAD` | every child `failed`, no synthesis survivor | delete the dir, or re-run the expedition fresh via its issue |
| `GENUINE_FAILURE` | leaf body <200 chars + `Research failed`/`exit 1` | content is gone — re-run that angle via its issue, or leave the failed card |
| `STRAY_DIR` | dir with no `index.*` (placeholder/orphan) | confirm nothing links to it, then delete |
| `FALSE_FLAG` | real body (≥600 chars) but failure status/`validation_error` | strip the flag → set `status: success` in **leaf frontmatter + parent `children:` + manifest.json** (all three) |
| `MANIFEST_MISMATCH` | manifest child count ≠ child dirs on disk | add the missing angle to `manifest.json` (and parent `children:`) or remove the stray dir |
| `MISSING_COST` | leaf has no `cost_usd` | `backfillable` → restore from `.scout-result.json` `total_cost_usd`; `lost` → leave blank, content is fine |
| `MISSING_COVER` | `cover.svg` on disk, no `cover:` line | add `cover: cover.svg` to frontmatter |
| `MISSING_ISSUE` | leaf/single page with no `issue:` | backfill from the driving Scout issue; leave if no source exists |
| `SLUG_DOUBLED_DATE` | slug repeats its date (`2026-06-02-2026-06-02-…`) | early-failed/duplicate run — usually pairs with `DEAD`; delete or re-run |
| `SLUG_REPEAT_TOKEN` | Place-Region-Place doubling (`taichung-taiwan-taichung`) | duplicate/orphaned run — verify against the clean run, merge unique angles, delete the orphan |
| `LEDGER_MISMATCH` | leaf ledger lost citations, or empty-url / non-JSON line | re-run if citations truncated; fix the malformed ledger line |

**The judgment call that matters:** `GENUINE_FAILURE` vs `FALSE_FLAG`. Both carry a failure status. The discriminator is body size — tiny body = content is gone (re-run); substantial body = the flag is lying (clean it). The scan splits them by char count; **eyeball the page before acting** when it's near the threshold.

## Step 3 — record and remediate

1. Write/refresh **`atlas/TRIAGE.md`**: `## Open` items first (what still needs a decision), `# Fixed` at the bottom (what you resolved, with links to verify). One concern per row; keep verify links.
2. Propose fixes grouped by category. **Get approval before mutating** — many fixes touch two repos: page/manifest edits land in **`atlas/`**, root-cause fixes land in **`scout/`** code. Per Scout boundaries, never `git`/`gh`/push without asking.
3. If a category that should be extinct reappears, treat it as a **Scout regression**, not just cleanup — these root causes were already fixed (ledger-validation non-fatal, dup-URL accepted, result-read non-fatal, the orphaned-JSON `jq` exit). A fresh occurrence means a code fix regressed; fix the cause in `scout/`, add a test, then clean the symptom in `atlas/`.

## Common mistakes

- **Deleting a `FALSE_FLAG` page** because it "failed" — it has real content behind the flag. Read the body first.
- **Backfilling cost on a `lost` page** — there's no `.scout-result.json` to read; the number is unrecoverable, and that's fine (the content isn't affected).
- **Fixing the symptom only.** Stripping a false flag fixes one page; making the cause non-fatal in Scout prevents the next hundred.
- **Editing the leaf but not the parent/manifest.** A status lives in three places (leaf frontmatter, parent `children:`, `manifest.json`); a half-fix still renders the ⚠.
