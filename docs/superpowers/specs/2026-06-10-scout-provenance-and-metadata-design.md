# /scout provenance issue + reliable metadata — design

**Date:** 2026-06-10

## Problem

The local `/scout` slash command is agent-driven (the Claude session *is* the
researcher). Two things the CI flow records deterministically are lost:

1. **Provenance.** No GitHub issue is created, so the substantial originating
   prompt — a filled `_travelling/SKELETON.md` Template A (~50 lines: scope,
   pace, budget, quality bars, 7 axes) — is not preserved anywhere linked to the
   published expedition. The artifact keeps only the one-line sharpened `topic:`.
2. **Metadata.** Child agents are *instructed* to self-stamp `model`,
   `duration_sec`, `cost_usd` (scout.md Step 4) but do so unreliably. Observed:
   `2026-06-10-a-first-visit-guide-to-southern-vietnam` — all 7 children missing
   all three, tripping triage `MISSING_MODEL` / `MISSING_DURATION` / `MISSING_COST`.

## Goals

1. Every `/scout` run leaves a **closed** GitHub issue carrying the verbatim
   prompt as its body and a `Published: <url>` comment; the parent frontmatter
   carries `issue: <n>` for the Atlas footer link.
2. `model` / `duration_sec` / `cost_usd` always land, independent of agent compliance.
3. Backfill the existing Southern Vietnam expedition.

## Non-goals

- Re-run / re-fire parity for local runs (remains CI-only).
- Changing the CI flow (`run.sh`, `run-decompose.sh`) or `backfill-metadata.sh`.

## Constraints from the triage scanner (`scan.py`)

- `MISSING_MODEL` / `MISSING_DURATION`: flagged on **every** node (parent + leaf).
- `MISSING_COST`: leaves only; cleared by any `cost_usd`. The value `"sub"` marks
  a subscription run.
- `MISSING_ISSUE`: leaves only, **exempt when `cost_usd: "sub"`**; parents are
  never checked.
- ⇒ Stamping `model` + `duration_sec` + `cost_usd: "sub"` on the children clears
  every health flag. **`issue:` is provenance-only**, not required for health.

## Components

### `scripts/local-issue.sh` (new)

Deterministic helper. **Non-fatal on any `gh` failure** (warn to stderr, exit 0,
empty result) so research/publish never blocks on issue plumbing. Uses `gh`'s
stored auth — no token env needed.

- `open <title> <prompt-file>` — derive the repo from
  `git -C "$SCOUT_DIR" remote get-url origin`; `gh issue create --title <title>
  --body-file <prompt-file>`; print the issue number (empty string on failure).
- `close <num> <url>` — `gh issue comment <num> --body "Published: <url>"`, then
  `gh issue close <num>`. No-op when `<num>` is empty.

Env: `SCOUT_DIR`.

### `scripts/inject-run-metadata.sh <research-dir>` (new)

Idempotent frontmatter stamper, mirroring `inject_cover.sh`'s "deterministic,
agent-independent" role. **Only inserts a field when absent; never overwrites an
existing value.** Reuses the awk "insert before the 2nd `---`" technique from
`backfill-metadata.sh`.

Env/args: `MODEL` (required, friendly label e.g. `"Opus 4.8"`),
`COST` (default `"sub"`), `ISSUE` (optional).

- **Parent** `index.{md,html}`: stamp `model`, `cost_usd`, and `issue` (when
  `ISSUE` set). Leave `duration_sec` if present; else set it to the manifest
  wall-clock (`max(end) − min(start)`).
- **Each child** (iterate `manifest.json` slugs; fall back to child dirs): stamp
  `model`, `cost_usd`, `duration_sec = end − start` from that child's manifest
  entry, and `issue` when `ISSUE` is set (mirrors the CI flow, which stamps the
  issue number on every node, so a child page viewed standalone keeps the backlink).

### `scout.md` edits

- **Step 1:** persist the raw, pre-sharpen topic input **verbatim** to a temp
  file (the original pasted prompt, before sharpening rewrites it) — used as the
  issue body.
- **Step 4 / Step 5:** remove the per-agent "must write `model` / `duration_sec`
  / `cost_usd`" requirements (lines ~66-68, ~102, ~107). Agents keep producing
  content, citations, summary, tags, and the cover trigger.
- **Step 6 (publish), ordered:**
  1. `ISSUE=$(SCOUT_DIR=… bash scripts/local-issue.sh open "<brief title>" <prompt-file>)`
  2. `MODEL="<session label>" ISSUE="$ISSUE" bash scripts/inject-run-metadata.sh "$PARENT_DIR"`
  3. existing `add-to-series.sh` + `publish.sh` → capture `Published: <url>`
  4. `bash scripts/local-issue.sh close "$ISSUE" "<url>"`

### Part C — backfill Southern Vietnam

- `MODEL="Opus 4.8" bash scripts/inject-run-metadata.sh \
  atlas/research/2026-06-10-a-first-visit-guide-to-southern-vietnam`
  → fills the 7 children (`model`, `duration_sec` from manifest, `cost_usd: "sub"`).
  Parent already complete.
- Retro-creating the issue (prompt body from `_travelling/vietnam/`) is **optional
  and gated on explicit user confirmation** (outward action). Default if
  unconfirmed: leave `issue:` unset — health is already clear.

## Testing (TDD)

- `tests/test_local_issue.sh` — stub `gh` on `PATH`: `open` passes title +
  `--body-file` with the verbatim prompt and prints the parsed number; repo
  derived from the remote; `close` emits the `Published:` comment then close; a
  `gh` failure yields exit 0 + empty number.
- `tests/test_inject_run_metadata.sh` — fixture parent + `manifest.json` +
  children missing fields: `model`/`cost` stamped on all nodes; child
  `duration_sec` = `end − start`; parent `duration_sec` from wall-clock when
  absent and preserved when present; `issue:` on parent only; re-run is a no-op;
  pre-existing values untouched.
- All existing `scout` tests continue to pass.

## Rollout

Forward changes (A + B) land in the `scout` repo. The Southern Vietnam backfill
(C) edits the `atlas` working tree and is committed separately. No CI changes.
