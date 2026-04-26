# Research decomposition — design spec

**Date:** 2026-04-26
**Status:** Design approved, awaiting implementation plan
**Origin:** GitHub issue [Laoujin/Scout#10](https://github.com/Laoujin/Scout/issues/10)

## Problem

Wide topics submitted at `expedition` depth get a single research artifact that under-represents some angles. Issue #10 ("Development work on the go") mixes Slack remote control, branch/PR automation, Synology deployment, subdomain routing, and orchestration — five independent sub-systems crammed into one expedition. Risk: thin coverage, forgotten angles, no audit trail per angle.

## Goal

Let Scout propose a decomposition during sharpening, let the user edit the proposal in place, and run each accepted sub-topic as its own research artifact. Produce a parent overview page that ties the children together. Stay within Scout's existing GitHub-Issue-driven, self-hosted-runner pipeline — no new infrastructure.

## Non-goals

- Spawning separate GitHub issues per sub-topic (kept as approach B in brainstorming, rejected: too much issue-juggling for one expedition).
- Per-topic format override (kept uniform per parent issue; reduces parsing surface).
- Cross-runner matrix fan-out (single self-hosted runner; children run sequentially within one job).
- New auth/storage. Pipeline state lives in the directory layout under `atlas/research/<DATE>-<slug>/`.

## High-level flow

```
1. User opens [research] issue
2. sharpen-on-open
   ├── Claude judges whether topic is multi-angled (T2)
   ├── Multi-angled  → emits sharpened-topic + Sub-topics list with
   │                  recommended (depth) per child
   └── Narrow        → emits today's comment, unchanged
3. User edits the bot comment in place
   ├── tick / untick sub-topics
   ├── edit (depth) prefix
   ├── add or remove sub-topic lines
   └── tick "Start research" -or- "Research as one expedition instead"
4. Workflow trigger: issue_comment edited, bot author, Start ticked
5. Parent run (run-decompose.sh)
   ├── re-parse current comment state
   ├── for each ticked child, sequentially:
   │   ├── if child folder has non-placeholder index → skip (resumability)
   │   ├── else invoke run.sh with child topic + child depth + parent format
   │   └── on failure or empty output → write failure placeholder
   ├── synthesis pass iff ≥2 children produced real output
   └── publish.sh — commits, pushes, comments URL
6. Issue handling
   ├── all children succeeded → close issue (existing behavior)
   └── any child failed       → leave issue open, post soft-fail comment.
                                 User re-edits + re-ticks Start to resume.
```

## Bot comment template

When decomposition is proposed:

````markdown
**Sharpened proposal**

```scout-topic
<one-paragraph topic statement>
```

This topic has several independent angles. Tick the ones to research as
part of this expedition; each becomes its own page, and the parent
produces an overview that ties them together.

### Sub-topics

- [ ] (survey) **<title>** — <one-line rationale>
- [ ] (expedition) **<title>** — <one-line rationale>
- [ ] (recon) **<title>** — <one-line rationale>

### Go

- [ ] **Start research** (runs every ticked sub-topic in parallel and
      generates an overview page)
- [ ] **Research as one expedition instead** (skip decomposition)
````

When decomposition is not proposed (T2 judges narrow): today's bot comment, unchanged — single Start checkbox, no Sub-topics section, no escape hatch.

### Sharpener heuristic for recommended depths

| Child profile | Recommended depth |
|---|---|
| Narrow, well-bounded angle | `recon` |
| Standard angle, single-pass plus reflect | `survey` (default) |
| Itself wide enough to warrant algorithmic decomposition | `expedition` |

The sharpener defaults to `survey` and escalates to `expedition` only when a sub-topic is itself multi-angled. This avoids stacking decomposition-of-decomposition (each `expedition` child internally spawns 3–8 parallel sub-agents, so 5 expedition children × 6 sub-agents = 30 concurrent Claude sessions — runs hot, costs balloon).

## Parser contract

`lib-issue-parse.sh` gains parsing for the sub-topics list.

| Element | Pattern | Notes |
|---|---|---|
| Sharpened topic | existing `scout-topic` fenced block | unchanged |
| Sub-topics section | between `### Sub-topics` and next `### ` heading | absence ⇒ narrow mode |
| Sub-topic line | `^\s*[-*]\s*\[([ xX])\]\s*(?:\(([a-z]+)\)\s*)?\*\*(.+?)\*\*(?:\s*[—-]\s*(.+))?$` | groups: checked, depth (optional), title, rationale (optional) |
| Depth tokens | `recon \| survey \| expedition` (display) and `ceo \| standard \| deep` (internal) | case-insensitive, alias-mapped |
| Start research | `- [x] **Start research**` | triggers parent run in decompose mode |
| Research as one | `- [x] **Research as one expedition instead**` | triggers existing single-pass behavior |

The regex shown is the canonical line shape. The parser implementation tries this pattern first, then falls back to permissive variants per the lenience rules below.

### Lenience rules (hand-edited markdown)

- Case-insensitive on depth tokens.
- Both `-` and `*` bullets accepted; leading whitespace tolerated.
- Missing rationale (title only) accepted.
- Missing `(depth)` prefix → defaults to `survey`.
- **Fuzzy depth matching:** unknown tokens within edit-distance ≤ 2 of any accepted token snap to that token (`suvey`→`survey`, `expdition`→`expedition`); genuinely unrecognizable → `survey` default.
- No bot comment-back on parse issues — workflow logs every coercion to its run output for traceability.

### Mutual exclusion

If both Start checkboxes are ticked simultaneously, **"Research as one expedition instead" wins** (safest fallback to existing behavior). The Sub-topics section is left untouched in the bot comment. Workflow logs which path it picked.

## Pipeline changes

### Files added or modified

```
.github/workflows/research.yml
  ├── sharpen-on-open        MODIFIED: skill emits sub-topics when wide
  ├── resharpen-on-comment   MODIFIED: same skill change applies
  ├── research               MODIFIED: dispatches to run.sh OR
  │                                    run-decompose.sh based on
  │                                    which Start checkbox was ticked
  └── research-dispatch      UNCHANGED (manual /scout flow stays single-pass)

scripts/
  ├── sharpen.sh             UNCHANGED
  ├── run.sh                 UNCHANGED (leaf orchestrator, used by both modes)
  ├── run-decompose.sh       NEW (parent orchestrator)
  ├── lib-issue-parse.sh     EXTENDED: sub-topics parsing + fuzzy depth
  ├── publish.sh             UNCHANGED (parent uses same publish path)
  └── research-from-issue.sh MODIFIED: branches on Sub-topics presence
                                       and which Start was ticked

skills/scout/
  ├── sharpen.md             MODIFIED: decomposition judgment + emission
  ├── SKILL.md               UNCHANGED
  ├── deep.md                UNCHANGED
  └── synthesis.md           NEW: instructions for the parent overview pass

atlas/
  ├── _layouts/expedition.html        NEW
  ├── _includes/research-children.html NEW (children-card grid)
  └── _config.yml                      MODIFIED (palette gains --expedition token)
```

### `run-decompose.sh` shape

```
1. Parse comment → list of {slug, title, depth, rationale} per ticked child
2. Create atlas-checkout/, mkdir parent atlas/research/<DATE>-<slug>/
3. Loop sequentially over children:
     child_dir = atlas/research/<DATE>-<slug>/<child-slug>/
     If wall-clock >= SOFT_TIMEOUT:
       write skipped placeholder ("soft timeout reached before start")
       continue
     If child_dir/index.{md,html} exists AND its frontmatter `status`
       is absent or != "failed":
         skip (resumability)
         continue
     remaining = HARD_TIMEOUT - elapsed
     timeout ${remaining}s bash run.sh \
       TOPIC=child.title DEPTH=child.depth FORMAT=parent.format \
       RESEARCH_DIR=child_dir
       on non-zero exit OR empty output → failure placeholder
4. Compute success_count = number of children with non-placeholder output
5. If success_count >= 2:
     invoke Claude with skills/scout/synthesis.md
     reads each child_dir/index.md (success or failure)
     writes parent index.md (synthesis prose + auto-generated children index)
   Else:
     write parent index.md auto-only (no synthesis prose)
6. Write parent frontmatter (layout: expedition, aggregate stats,
   children: [...] with status per child)
7. publish.sh — commits, pushes, posts URL.
   If any failure placeholder exists → leave issue open + soft-fail comment.
```

### Concurrency

Single self-hosted runner. Children run **sequentially within one job**; per-child internal parallelism preserved (an `expedition` child still spawns its 3–8 parallel sub-agents internally). Wall-clock cost: roughly the sum of child runtimes plus a synthesis pass.

### Safeguards

| Knob | Default | Behavior |
|---|---|---|
| `SCOUT_MAX_CHILDREN` | 8 | Sharpener instructed not to propose more; workflow truncates with a warning if user adds beyond. Mirrors expedition's internal sub-agent cap. |
| `SCOUT_DECOMPOSE_SOFT_TIMEOUT` | 4h | Wall-clock budget for *starting* new children. Already-running child continues. Not-yet-started children get "skipped (soft timeout)" placeholder. |
| `SCOUT_DECOMPOSE_HARD_TIMEOUT` | 4h20m | Absolute upper bound on any single child run. Implemented as `timeout` ceiling per child invocation. In-flight child at hard deadline → killed, marked failed with reason "hard timeout". |
| `SCOUT_CHILD_DEFAULT_DEPTH` | survey | Used when sharpener doesn't recommend a depth or parser falls back. |

Synthesis pass runs after the children loop terminates (soft or hard). No additional cap — bounded by Claude's typical synthesis output (~10 min). Worst-case total wall-clock: ~4h30m.

### Resumability

The directory layout *is* the state machine. After a partial-failure publish, the user re-edits the comment and re-ticks Start. `run-decompose.sh` step 3 walks the parent folder; child folders with a non-placeholder `index.md` are skipped, placeholders and missing folders are re-run. No external state store needed.

## Atlas changes

### New layout: `_layouts/expedition.html`

Used by parent overview pages. Children continue to use `_layouts/research.html`. Default front-matter mapping in `_config.yml` is updated so files declaring `layout: expedition` resolve to it.

**Visual structure (top → bottom):**

1. **Hero band** — title, **expedition badge** (replaces depth badge), date, aggregate citation count, aggregate reading time, children count (e.g. "5 angles · 3 succeeded · 2 placeholders"), back-link to Atlas home.
2. **Sharpened topic** — quote block from frontmatter.
3. **Synthesis section** (O3 prose) — rendered iff `synthesis: true` in frontmatter.
4. **Children grid** — rendered from `children:` frontmatter array via `_includes/research-children.html`.
5. **Footer** — existing.

### New include: `_includes/research-children.html`

Iterates `page.children`. Two card states:

| State | Rendering |
|---|---|
| `status: success` | Normal card, configured variant (v1–v7), title, summary, depth pill, citation count. Whole card links to `<parent>/<child-slug>/`. |
| `status: failed` | Greyed-out card, same dimensions, "failed" badge in corner, failure reason in body slot, depth pill faded. **Not a link.** |

### Frontmatter — parent `index.md`

```yaml
---
layout: expedition
title: <parent title>
date: 2026-04-26
topic: <sharpened topic statement>
format: <inherited>
synthesis: true                # false when 0 or 1 children succeeded
citations: 87                  # sum across successful children
reading_time_min: 42           # sum across successful children
claude_cost: 12.40             # sum across all child attempts (incl. failed)
claude_duration_sec: 14820     # parent run wall-clock
children:
  - slug: slack-claude-code
    title: Slack ↔ Claude Code remote control
    depth: expedition
    status: success
    summary: <pulled from child frontmatter>
    citations: 32
    reading_time_min: 12
  - slug: routing
    title: Per-feature subdomain routing
    depth: expedition
    status: failed
    failure_reason: hard timeout
    attempted_at: 2026-04-26T18:42:00Z
---
```

### Frontmatter — child `index.md`

Same as today's research frontmatter. Children stay on the `research` layout regardless of state. Failure placeholders use the same shape with `status: failed` and a `failure_reason` field.

### Atlas home grid

Parent expedition appears as **one card** on the Atlas home (N1 nesting). Children don't appear on the home grid. The expedition card on the home renders with:

- The expedition badge instead of a depth badge.
- An **"N angles" overlay** in the corner so home-grid browsers can tell at a glance that it's a multi-page artifact rather than a leaf.

### Theming

The `expedition` layout respects the same `_config.yml` skeleton/palette/cards triple as the rest of Atlas. The expedition badge introduces one new color token (`--expedition`) per palette file; partial gracefully degrades if missing.

## Failure handling (F2)

- **Publish always runs**, even on partial failure.
- **Successful children** publish normally to `<parent>/<child-slug>/index.md`.
- **Failed children** publish a placeholder `index.md` with `status: failed`, `failure_reason`, `attempted_at`, and the chosen `depth`. The placeholder document body is one paragraph stating the failure reason.
- **Synthesis** runs iff ≥2 children have non-placeholder output *at the moment the children loop terminates*. With 0 or 1 successes, the parent `index.md` is auto-generated only (no synthesis prose), still publishes. On a resumed run that brings the success count to ≥2, the next parent run will produce synthesis prose.
- **Issue stays open** if any child is a placeholder. A soft-fail comment lists failed child slugs and reasons.
- **Resume** by re-editing the comment and re-ticking Start. `run-decompose.sh` skips children with a non-placeholder `index.md`; placeholders and missing folders are re-run.

## Testing

### Bash unit tests (new)

| Test file | Coverage |
|---|---|
| `tests/test_lib_issue_parse_subtopics.sh` | Sub-topic line parsing variants, fuzzy depth matching, alias mapping, mutually-exclusive Start checkboxes, narrow-mode detection. |
| `tests/test_run_decompose_resumability.sh` | Mixed-state parent folder → only invokes leaf for placeholders + missing. Stubs `run.sh` to record invocations. |
| `tests/test_run_decompose_synthesis_gate.sh` | 0 / 1 / 2+ successes → synthesis invoked respectively never / never / once. Stubs synthesis Claude call. |
| `tests/test_run_decompose_timeout.sh` | Soft timeout: not-yet-started children get skipped placeholder, loop terminates. Hard timeout: in-flight stub past hard ceiling killed and marked failed. |
| `tests/test_failure_placeholder.sh` | Placeholder frontmatter shape: required keys, `layout: research`. |

Existing `tests/test_publish.sh` gains a mixed-success case verifying issue-stays-open + soft-fail comment.

### Sharpener / synthesis (snapshot, not assertion)

T2 judgment and synthesis prose are Claude calls — not deterministically testable. Treat as snapshot fixtures:

- `tests/fixtures/sharpen/wide_topic.txt` (issue #10's body) → record sharpener output to `wide_topic.expected.md`. Re-run on prompt changes; manually review diff.
- `tests/fixtures/sharpen/narrow_topic.txt` → expects no Sub-topics section.
- Synthesis: feed three child `index.md` fixtures, snapshot output. Manual review.

Snapshot tests are guard-rails against unintended drift, not correctness assertions.

### Atlas

No automated tests today. Add:

- `_previews/expedition.md` — full success case
- `_previews/expedition-partial.md` — mixed success/failed children

Visual review only via existing `serve.ps1`.

## Rollout

Three independently shippable stages:

1. **Sharpener-only.** T2 judgment + sub-topic emission template. Workflow does NOT yet act on Sub-topics; Start research still runs single-pass `run.sh`. Iterate on decomposition quality with zero blast radius.
2. **Decompose pipeline (no Atlas L2).** Wire `run-decompose.sh`, parser extension, partial-failure publish. Children render with existing `research` layout; parent renders as plain `research` with auto-generated children list.
3. **Atlas L2 + home overlay.** New `expedition` layout, children-card states, expedition badge, "N angles" home overlay. Pure presentation.

Each stage merges independently. Stage 1 alone delivers the "Claude notices angles" feedback loop the issue originated from.

## Observability

- Per-child `claude_cost` and `claude_duration_sec` injected by existing `inject_cost.sh`. Parent frontmatter aggregates.
- New: `manifest.json` in parent folder listing each child's slug, depth, status, start/end timestamps, exit code. Drives the soft-fail comment template and aids debugging long runs.
