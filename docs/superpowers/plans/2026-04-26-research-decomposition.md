# Research Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Scout decompose wide research topics into per-angle child runs the user controls via the existing GitHub Issue + bot-comment flow, with a parent overview page in Atlas that synthesises the children.

**Architecture:** Three independently shippable stages bolted onto the existing pipeline:

1. **Sharpener** judges multi-angled topics and emits a sub-topics block alongside the sharpened paragraph.
2. **Decompose pipeline** — a new `run-decompose.sh` parent orchestrator iterates over user-ticked sub-topics (each running the existing `run.sh` as a child), then writes a synthesis pass. F2 partial-failure semantics with directory-as-state-machine resumability.
3. **Atlas L2** — a new `expedition` layout for the parent overview, a children-card grid include with success/failed states, and an "N angles" home-grid overlay.

**Tech Stack:** Bash 5 + GNU coreutils + `awk`/`sed`/`grep` (existing Scout patterns), `gh` CLI, GitHub Actions, Claude Code (`claude --dangerously-skip-permissions --print --output-format json`), Jekyll 4 (Atlas).

---

## File Structure

| Stage | Action | Path | Responsibility |
|---|---|---|---|
| 1 | Modify | `scout/skills/scout/sharpen.md` | Add T2 judgment + sub-topics emission instructions |
| 1 | Create | `scout/tests/fixtures/sharpen/wide_topic.txt` | Issue-#10-style wide topic input |
| 1 | Create | `scout/tests/fixtures/sharpen/narrow_topic.txt` | Single-angle input |
| 1 | Create | `scout/tests/fixtures/sharpen/wide_topic.expected.md` | Captured snapshot |
| 1 | Create | `scout/tests/fixtures/sharpen/narrow_topic.expected.md` | Captured snapshot |
| 1 | Create | `scout/tests/test_sharpen_snapshots.sh` | Snapshot runner |
| 2 | Modify | `scout/scripts/lib-issue-parse.sh` | Add `parse_sub_topics`, `parse_start_choice`, fuzzy depth, alias-bidirectional mapping |
| 2 | Create | `scout/tests/test_lib_issue_parse_subtopics.sh` | Unit tests for parser extension |
| 2 | Modify | `scout/scripts/issue-comment.sh` | Render sub-topics block + escape-hatch checkbox when sharpener emitted them |
| 2 | Create | `scout/skills/scout/synthesis.md` | Skill instructions for the parent overview synthesis pass |
| 2 | Create | `scout/scripts/run-decompose.sh` | Parent orchestrator |
| 2 | Create | `scout/tests/test_run_decompose_resumability.sh` | Verify skip-on-existing |
| 2 | Create | `scout/tests/test_run_decompose_synthesis_gate.sh` | Verify ≥2-success synthesis trigger |
| 2 | Create | `scout/tests/test_run_decompose_timeout.sh` | Verify soft/hard timeout |
| 2 | Create | `scout/tests/test_failure_placeholder.sh` | Verify placeholder frontmatter shape |
| 2 | Modify | `scout/tests/test_publish.sh` | Add mixed-success case |
| 2 | Modify | `scout/scripts/research-from-issue.sh` | Branch on Sub-topics presence + Start choice |
| 2 | Modify | `scout/scripts/publish.sh` | Soft-fail comment template lists failed children |
| 2 | Modify | `scout/.github/workflows/research.yml` | Trigger condition includes "Research as one expedition instead" variant; resharpen-on-comment job harvests `### Sub-topics` from prior bot comment |
| 2 | Modify | `scout/scripts/sharpen.sh` | Forward optional `PREVIOUS_SUB_TOPICS` env into Claude prompt |
| 3 | Create | `atlas/_layouts/expedition.html` | Parent overview layout |
| 3 | Create | `atlas/_includes/research-children.html` | Children-card grid with success/failed states |
| 3 | Modify | `atlas/_config.yml` | Add `--expedition` palette token mapping |
| 3 | Modify | `atlas/assets/research.css` | Expedition badge + children-grid + failed-card styles |
| 3 | Modify | `atlas/_includes/cards/v1.html` (and similar v2–v7 if home grid uses multiple variants) | Render expedition badge + "N angles" overlay when `page.children` present |
| 3 | Create | `atlas/_previews/expedition/index.html` | Full success preview |
| 3 | Create | `atlas/_previews/expedition-partial/index.html` | Mixed success/failed preview |

Working directory for all `bash` and `git` commands below is `/mnt/c/Users/woute/Dropbox/Personal/Programming/UnixCode/projects/Scout+Atlas/scout` unless noted (Atlas tasks switch to `…/atlas`).

---

## Stage 1 — Sharpener emits sub-topics (informational only)

**Outcome (as actually delivered, 2026-04-26):**

When the sharpener judges a topic multi-angled, it appends a `scout-subtopics` fenced block to its output. `issue-comment.sh` was modified (pulled forward from Task 4) to split `TOPIC_ONLY` from `SUB_TOPICS_BLOCK`: the paragraph goes inside the existing `scout-topic` fenced block; the sub-topics render as a separate `### Sub-topics` markdown section followed by a `### Go` header and the existing single `Start research` checkbox. The pull-forward was required because the original "leave the block inside `scout-topic`" approach silently corrupted `TOPIC` for every wide-topic single-pass run (the bare-fence awk extractor in `research-from-issue.sh` exits at the first `^```$` it sees, which would be the inner closing fence). With the split in place, downstream extraction works correctly and the workflow trigger + `run.sh` invocation remain unchanged.

**Stage 1 ships sub-topics as informational only.** Ticking `Start research` still runs single-pass `run.sh`. The bot comment includes a one-sentence disclaimer ("The list below is informational for now — Start research will run a single expedition over the whole topic. Per-angle decomposition is being wired in a follow-up.") so users aren't confused by the inert checkboxes on each sub-topic line.

**Deferred to Stage 2 (originally bundled in Task 4):**
- Adding the `Research as one expedition instead` escape-hatch checkbox.
- Replacing the "informational for now" disclaimer with the real "Tick the ones to research..." text.
- Updating the workflow trigger (Task 11) to fire on either Start checkbox variant.
- Wiring `research-from-issue.sh` (Task 10) to branch on which checkbox was ticked.

The work the original Task 4 prescribed for `issue-comment.sh` is therefore ~50% done. Stage 2's Task 4 is reduced to the items in the deferred list above; the `TOPIC_ONLY` / `SUB_TOPICS_BLOCK` split, the `### Sub-topics` rendering, and the `### Go` header are already in place at the Stage 1 ship state.

### Task 1: Sharpener output contract — fixtures + snapshot harness

**Files:**
- Create: `scout/tests/fixtures/sharpen/wide_topic.txt`
- Create: `scout/tests/fixtures/sharpen/narrow_topic.txt`
- Create: `scout/tests/test_sharpen_snapshots.sh`

- [ ] **Step 1.1: Create the wide-topic fixture (issue #10's body, verbatim).**

```bash
cat > tests/fixtures/sharpen/wide_topic.txt <<'EOF'
- Claude Code and I chat on Slack about a project
- Slack channel per project maybe?
- At some point I give a go
- Claude Code implements the feature/bugfix
- A branch, and a PR are created
- The change is deployed on my NAS (Synology)
- The change is exposed via a url (ex: ProjectName-FeatureX.sangu.be)

I need a workflow for this
EOF
```

- [ ] **Step 1.2: Create the narrow-topic fixture.**

```bash
cat > tests/fixtures/sharpen/narrow_topic.txt <<'EOF'
Compare ripgrep, ag, ack, and grep for searching a 50k-file repo.
Decision-only.
EOF
```

- [ ] **Step 1.3: Create the snapshot harness.**

```bash
cat > tests/test_sharpen_snapshots.sh <<'EOF'
#!/usr/bin/env bash
# Snapshot tests for skills/scout/sharpen.md.
#
# A snapshot test invokes scripts/sharpen.sh against a fixture topic,
# diffs the output against a checked-in *.expected.md, and reports drift.
# These are guard-rails, not correctness assertions — manually review
# diffs after intentional prompt changes, then re-capture with:
#   UPDATE_SNAPSHOTS=1 bash tests/test_sharpen_snapshots.sh
#
# Requires: an interactive Claude session (the harness invokes sharpen.sh
# which calls `claude`). Skips quietly if SCOUT_SKIP_CLAUDE=1.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/sharpen"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

if [ "${SCOUT_SKIP_CLAUDE:-}" = "1" ]; then
  echo "SCOUT_SKIP_CLAUDE=1 — skipping snapshot tests."
  exit 0
fi

for fix in "$FIXTURES"/*.txt; do
  base="$(basename "$fix" .txt)"
  expected="$FIXTURES/$base.expected.md"
  topic="$(cat "$fix")"
  actual="$(RAW_TOPIC="$topic" DEPTH=expedition FORMAT=auto \
            bash "$REPO_ROOT/scripts/sharpen.sh")"
  if [ "${UPDATE_SNAPSHOTS:-}" = "1" ]; then
    printf '%s\n' "$actual" > "$expected"
    pass "$base (captured)"
    continue
  fi
  if [ ! -f "$expected" ]; then
    fail "$base: no expected snapshot at $expected (run with UPDATE_SNAPSHOTS=1)"
    continue
  fi
  if diff -u "$expected" <(printf '%s\n' "$actual") >/dev/null; then
    pass "$base"
  else
    fail "$base: output drift — diff:"
    diff -u "$expected" <(printf '%s\n' "$actual") | sed 's/^/    /'
  fi
done

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_sharpen_snapshots.sh
```

- [ ] **Step 1.4: Run the harness — expect "no expected snapshot" failures.**

```bash
bash tests/test_sharpen_snapshots.sh
```

Expected: two FAIL lines (one per fixture, "no expected snapshot at ..."), exit code 1. This proves the harness is wired correctly and the fixtures are present.

### Task 2: Update `sharpen.md` with T2 judgment + sub-topics emission

**Files:**
- Modify: `scout/skills/scout/sharpen.md`

The output section currently demands "One paragraph. No preamble." We extend it: still one paragraph for the topic, plus an *optional* fenced `scout-subtopics` block when the topic is genuinely multi-angled.

- [ ] **Step 2.1: Replace the "Output" section.**

Replace the current `## Output` and `## Example` sections at lines 46–62 with:

```markdown
## Output

Always emit the sharpened topic as one paragraph. No preamble ("Here is..."), no quotes, no bullet list, no markdown headers, no explanation of what you changed. Just the paragraph, ready to be passed verbatim to the research playbook.

**Then judge whether the topic is multi-angled.** A topic is multi-angled when it bundles independent sub-systems each worth their own deep dive (e.g., issue #10 mixes Slack remote control, branch/PR automation, deployment, routing, and orchestration). It is NOT multi-angled when the angles share a common axis the research already compares along (e.g. "compare ripgrep vs ag vs ack" — single comparison, not multi-angled).

If multi-angled and `Depth: deep` (expedition), append a fenced `scout-subtopics` block listing 2–8 sub-topics. Otherwise emit nothing after the paragraph.

### Sub-topics block format

````
```scout-subtopics
- (depth) **Title** — one-line rationale.
- (depth) **Title** — one-line rationale.
```
````

- `depth` is one of `recon` / `survey` / `expedition`.
- Default each child to `survey`; downgrade to `recon` for narrow angles; upgrade to `expedition` only when the sub-topic is itself multi-angled.
- Avoid `expedition` for more than one or two children — each `expedition` child internally spawns 3–8 parallel sub-agents, so stacking them runs hot.
- Cap at 8 sub-topics.
- Every sub-topic must have a `(depth)` prefix and a `— rationale`. Title in `**bold**`.
- Don't propose sub-topics that are mere sub-questions of one angle — those belong to the angle's own deep dive.

### Examples

**Narrow input:**
```
Raw topic: Compare ripgrep, ag, ack, and grep for searching a 50k-file repo. Decision-only.
Depth: standard
Format: auto
```

Output:
```
Decision framework comparing ripgrep, ag, ack, and grep for repository-scale code search in 2026, focused on speed on a 50k-file tree, ergonomic fit (PCRE/regex flavor, smart-case, gitignore awareness), packaging maturity, and the maintenance state of each tool.
```

(No `scout-subtopics` block — single comparison axis.)

**Wide input:**
```
Raw topic: I want to chat with Claude Code on Slack about a project, give a go, have a feature branch built, deployed to my Synology, and exposed via ProjectName-FeatureX.sangu.be. I need a workflow for this.
Depth: deep
Format: auto
```

Output:
```
Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology. Cover the wiring, state, and failure modes that tie the pieces together; favor production-ready open-source components in 2026.
```
```scout-subtopics
- (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, approval/handoff, mobile UX. Needs survey of GitHub App vs Agent SDK vs self-hosted bot.
- (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout in the loop.
- (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch, build pipeline, teardown on branch delete.
- (expedition) **Per-feature subdomain routing** — Wildcard `*.sangu.be` reverse proxy (Traefik/Caddy/nginx), wildcard TLS via Let's Encrypt DNS-01, dynamic config from branch metadata.
- (recon) **Orchestration and state** — Glue tying the four pieces above; where state lives; failure modes and recovery.
```
```

- [ ] **Step 2.2: Capture the snapshots manually.**

```bash
UPDATE_SNAPSHOTS=1 bash tests/test_sharpen_snapshots.sh
```

Expected: two PASS lines ("captured"). Two new files at `tests/fixtures/sharpen/wide_topic.expected.md` and `tests/fixtures/sharpen/narrow_topic.expected.md`.

- [ ] **Step 2.3: Manually review the captured snapshots.**

Open both `*.expected.md` files. Verify:

- `narrow_topic.expected.md`: contains a single paragraph, NO `scout-subtopics` block.
- `wide_topic.expected.md`: contains a paragraph followed by a `scout-subtopics` fenced block with 2–8 entries, each line matching the canonical regex `^- \(\w+\) \*\*.+\*\* — .+$`.

If either snapshot is wrong, edit `sharpen.md` and re-run with `UPDATE_SNAPSHOTS=1` until both look right. Commit only the version you've reviewed.

- [ ] **Step 2.4: Run the harness against the committed snapshots.**

```bash
bash tests/test_sharpen_snapshots.sh
```

Expected: two PASS lines. Exit 0.

### Stage 1 commit checkpoint

- [ ] **Step S1.C: Commit Stage 1.**

```bash
git add skills/scout/sharpen.md \
        tests/fixtures/sharpen/ \
        tests/test_sharpen_snapshots.sh
git commit -m "feat(sharpen): emit sub-topics block for multi-angled expeditions"
```

(Per `CLAUDE.md`: imperative subject ≤72 chars, no Co-Authored-By.)

---

## Stage 2 — Decompose pipeline

**Outcome:** When a sub-topics block is present and the user ticks **Start research**, the workflow runs `run-decompose.sh` which iterates over ticked sub-topics, invokes `run.sh` per child at the chosen depth, and writes a parent overview (synthesis when ≥2 children succeeded, auto-only otherwise). When the user ticks **Research as one expedition instead**, the existing `run.sh` runs unchanged. Partial failures publish placeholders and keep the issue open for resumption.

### Task 3: Extend `lib-issue-parse.sh` with sub-topic parsing

**Files:**
- Modify: `scout/scripts/lib-issue-parse.sh`
- Create: `scout/tests/test_lib_issue_parse_subtopics.sh`

> **Note for Stage 2:** After Stage 1, the bot comment contains a `### Sub-topics` markdown section but **no `scout-subtopics` fenced block** (the fence is stripped by `issue-comment.sh`). The parser must read the markdown section directly. The existing `_extract_section "$body" 'Sub-topics'` helper handles this correctly, but the test suite below should include at least one case using a *full real-shape bot-comment body* — header + blockquote + `scout-topic` fenced block + Sub-topics section + `### Go` + Start checkboxes — to verify the parser walks past the upstream `<!-- scout-topic-start --> ... <!-- scout-topic-end -->` markers and the `scout-topic` block without false positives. The isolated `### Sub-topics\n...` snippets below are the unit cases; add one integration-shape case before committing.

- [ ] **Step 3.1: Write the failing tests first.**

```bash
cat > tests/test_lib_issue_parse_subtopics.sh <<'EOF'
#!/usr/bin/env bash
# Tests for parse_sub_topics() and parse_start_choice() in lib-issue-parse.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-issue-parse.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"
  else fail "$label: expected [$expected], got [$actual]"; fi
}

# --- canonical sub-topic line ---
COMMENT=$'### Sub-topics\n- [x] (expedition) **Routing** — Wildcard TLS.\n- [ ] (recon) **Glue** — Orchestration angle.\n\n### Go\n- [ ] **Start research**\n- [ ] **Research as one expedition instead**\n'
parse_sub_topics "$COMMENT"
assert_eq "canonical: count" "2" "${#SUB_TOPICS[@]}"
assert_eq "canonical: line0 checked" "true"        "${SUB_TOPICS[0]##*|}"
assert_eq "canonical: line0 depth"   "deep"        "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "canonical: line0 title"   "Routing"     "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f3)"
assert_eq "canonical: line1 checked" "false"       "${SUB_TOPICS[1]##*|}"
assert_eq "canonical: line1 depth"   "ceo"         "$(echo "${SUB_TOPICS[1]}" | cut -d'|' -f2)"

# --- fuzzy depth tokens snap to nearest known token within distance 2 ---
COMMENT=$'### Sub-topics\n- [x] (suvey) **A** — typo.\n- [x] (expdition) **B** — typo.\n'
parse_sub_topics "$COMMENT"
assert_eq "fuzzy: suvey -> standard"     "standard" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "fuzzy: expdition -> deep"     "deep"     "$(echo "${SUB_TOPICS[1]}" | cut -d'|' -f2)"

# --- internal codes accepted as aliases ---
COMMENT=$'### Sub-topics\n- [x] (deep) **A** — internal.\n- [x] (CEO) **B** — case.\n'
parse_sub_topics "$COMMENT"
assert_eq "alias: deep stays deep"       "deep"     "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "alias: CEO -> ceo"            "ceo"      "$(echo "${SUB_TOPICS[1]}" | cut -d'|' -f2)"

# --- missing depth prefix defaults to standard ---
COMMENT=$'### Sub-topics\n- [x] **A** — no depth prefix.\n'
parse_sub_topics "$COMMENT"
assert_eq "missing depth: defaults"      "standard" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"

# --- unknown depth (distance >2) defaults to standard ---
COMMENT=$'### Sub-topics\n- [x] (gibberish) **A** — unknown token.\n'
parse_sub_topics "$COMMENT"
assert_eq "unknown depth: defaults"      "standard" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"

# --- bullet style + leading whitespace tolerated ---
COMMENT=$'### Sub-topics\n  * [x] (survey) **Asterisk** — alt bullet.\n'
parse_sub_topics "$COMMENT"
assert_eq "asterisk bullet ok"           "standard" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "asterisk bullet title"        "Asterisk" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f3)"

# --- absent Sub-topics section -> empty array ---
COMMENT=$'### Go\n- [ ] **Start research**\n'
parse_sub_topics "$COMMENT"
assert_eq "absent section: empty"        "0"        "${#SUB_TOPICS[@]}"

# --- parse_start_choice ---
COMMENT=$'### Go\n- [x] **Start research**\n- [ ] **Research as one expedition instead**\n'
parse_start_choice "$COMMENT"
assert_eq "start: decompose"             "decompose" "$START_CHOICE"

COMMENT=$'### Go\n- [ ] **Start research**\n- [x] **Research as one expedition instead**\n'
parse_start_choice "$COMMENT"
assert_eq "start: as_one"                "as_one"    "$START_CHOICE"

COMMENT=$'### Go\n- [x] **Start research**\n- [x] **Research as one expedition instead**\n'
parse_start_choice "$COMMENT"
assert_eq "start: both -> as_one wins"   "as_one"    "$START_CHOICE"

COMMENT=$'### Go\n- [ ] **Start research**\n- [ ] **Research as one expedition instead**\n'
parse_start_choice "$COMMENT"
assert_eq "start: neither"               "none"      "$START_CHOICE"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_lib_issue_parse_subtopics.sh
```

- [ ] **Step 3.2: Run — expect failure (functions don't exist yet).**

```bash
bash tests/test_lib_issue_parse_subtopics.sh
```

Expected: every assertion fails (or bash errors with `parse_sub_topics: command not found`). Confirms the test wiring is real.

- [ ] **Step 3.3: Implement `parse_sub_topics` and `parse_start_choice` in `lib-issue-parse.sh`.**

Append to `scripts/lib-issue-parse.sh` (after the existing `parse_issue_body`):

```bash
# --- Sub-topic parsing ----------------------------------------------------
#
# parse_sub_topics extracts the Sub-topics list from a bot comment body and
# populates the global SUB_TOPICS array. Each entry has the shape:
#   "<title>|<depth>|<rationale>|<checked>"
# where <depth> is the internal code (ceo/standard/deep) and <checked> is
# the literal string "true" or "false".
#
# Lenience rules (mirrors hand-edited markdown):
#  - either `-` or `*` bullets, leading whitespace tolerated
#  - depth tokens accept display names (recon/survey/expedition), internal
#    codes (ceo/standard/deep), case-insensitive
#  - unknown tokens within edit-distance ≤ 2 of any accepted token snap
#    to that token; otherwise default to `standard`
#  - missing `(depth)` prefix → defaults to `standard`
#  - missing `— rationale` accepted (rationale=empty)

# Levenshtein distance between two strings; pure bash; O(len1*len2). Fine
# for our 6-element token table and short inputs.
_lev() {
  local s="$1" t="$2"
  local m=${#s} n=${#t} i j cost
  if [ "$m" -eq 0 ]; then echo "$n"; return; fi
  if [ "$n" -eq 0 ]; then echo "$m"; return; fi
  declare -A d
  for ((i=0; i<=m; i++)); do d[$i,0]=$i; done
  for ((j=0; j<=n; j++)); do d[0,$j]=$j; done
  for ((i=1; i<=m; i++)); do
    for ((j=1; j<=n; j++)); do
      [ "${s:i-1:1}" = "${t:j-1:1}" ] && cost=0 || cost=1
      local del=$(( d[$((i-1)),$j] + 1 ))
      local ins=$(( d[$i,$((j-1))] + 1 ))
      local sub=$(( d[$((i-1)),$((j-1))] + cost ))
      local min=$del
      [ "$ins" -lt "$min" ] && min=$ins
      [ "$sub" -lt "$min" ] && min=$sub
      d[$i,$j]=$min
    done
  done
  echo "${d[$m,$n]}"
}

# Snap a depth token to the nearest known internal code, or "standard" if
# nothing is within edit-distance 2.
_snap_depth() {
  local input="$1"
  local lower
  lower="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    ceo|standard|deep) echo "$lower"; return ;;
    recon)             echo "ceo";      return ;;
    survey)            echo "standard"; return ;;
    expedition)        echo "deep";     return ;;
  esac
  local best="standard" best_d=99
  local cand cand_internal d
  for cand in recon ceo survey standard expedition deep; do
    d="$(_lev "$lower" "$cand")"
    if [ "$d" -le 2 ] && [ "$d" -lt "$best_d" ]; then
      best_d=$d
      case "$cand" in
        recon) cand_internal=ceo ;;
        survey) cand_internal=standard ;;
        expedition) cand_internal=deep ;;
        *) cand_internal=$cand ;;
      esac
      best="$cand_internal"
    fi
  done
  echo "$best"
}

# Populate SUB_TOPICS array from the comment body. Empty array if no
# `### Sub-topics` section is present.
parse_sub_topics() {
  local body="$1"
  SUB_TOPICS=()
  local section
  section="$(_extract_section "$body" 'Sub-topics')"
  [ -n "$section" ] || return 0
  while IFS= read -r line; do
    # strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # match: bullet [ ]/[x] (optional (depth)) **title** (optional — rationale)
    if [[ "$line" =~ ^[-*][[:space:]]+\[([\ xX])\][[:space:]]*(\(([a-zA-Z]+)\)[[:space:]]*)?\*\*([^*]+)\*\*([[:space:]]*[—-][[:space:]]*(.*))?$ ]]; then
      local checked_raw="${BASH_REMATCH[1]}"
      local depth_raw="${BASH_REMATCH[3]}"
      local title="${BASH_REMATCH[4]}"
      local rationale="${BASH_REMATCH[6]:-}"
      local checked="false"
      [[ "$checked_raw" =~ [xX] ]] && checked="true"
      local depth_internal
      if [ -n "$depth_raw" ]; then
        depth_internal="$(_snap_depth "$depth_raw")"
      else
        depth_internal="standard"
      fi
      SUB_TOPICS+=("${title}|${depth_internal}|${rationale}|${checked}")
    fi
  done <<< "$section"
}

# Determine which Start checkbox the user ticked.
#   "decompose"  — only `Start research` ticked
#   "as_one"     — `Research as one expedition instead` ticked (wins ties)
#   "none"       — neither
parse_start_choice() {
  local body="$1"
  local start_ticked=false as_one_ticked=false
  if printf '%s' "$body" | grep -qiE '^\s*-[[:space:]]+\[[xX]\][[:space:]]+\*\*Start research\*\*'; then
    start_ticked=true
  fi
  if printf '%s' "$body" | grep -qiE '^\s*-[[:space:]]+\[[xX]\][[:space:]]+\*\*Research as one expedition instead\*\*'; then
    as_one_ticked=true
  fi
  if $as_one_ticked; then
    START_CHOICE="as_one"
  elif $start_ticked; then
    START_CHOICE="decompose"
  else
    START_CHOICE="none"
  fi
  export START_CHOICE
}
```

- [ ] **Step 3.4: Run the tests — expect all pass.**

```bash
bash tests/test_lib_issue_parse_subtopics.sh
```

Expected: every PASS line printed, no FAIL lines, exit 0.

- [ ] **Step 3.5: Commit.**

```bash
git add scripts/lib-issue-parse.sh tests/test_lib_issue_parse_subtopics.sh
git commit -m "feat(parser): parse Sub-topics list with fuzzy depth + start choice"
```

### Task 4: Add escape-hatch checkbox + finalize disclaimer in `issue-comment.sh`

**Files:**
- Modify: `scout/scripts/issue-comment.sh`

> **Stage 1 already shipped half of this task.** The `TOPIC_ONLY` / `SUB_TOPICS_BLOCK` split, the `### Sub-topics` markdown section rendering, and the `### Go` header are all in place at Stage 1 ship state (commit `db90e1a` and predecessors). What remains is: replace the "informational for now" disclaimer with the real "Tick the ones..." text, and add the `Research as one expedition instead` checkbox under `### Go`.

- [ ] **Step 4.1: Update the wide branch's disclaimer + add the escape-hatch checkbox.**

In `scripts/issue-comment.sh`, find the wide branch (the `if [ -n "$SUB_TOPICS_BLOCK" ]; then` block). Make two changes:

1. Replace the disclaimer paragraph that currently reads:
   > `This topic has several independent angles. The list below is informational for now — Start research will run a single expedition over the whole topic. (Per-angle decomposition is being wired in a follow-up.)`

   with:

   > `This topic has several independent angles. Tick the ones to research as part of this expedition; each becomes its own page, and the parent produces an overview that ties them together. Edit a \`(depth)\` to override the recommended level.`

2. Under the existing `### Go` header, the wide branch currently has only:
   ```
   - [ ] **Start research** — tick this to publish to Atlas (depth: ...).
   ```
   Replace those two lines with the dual-checkbox version:
   ```
   - [ ] **Start research** (runs every ticked sub-topic in parallel and generates an overview page; depth: \`${DEPTH_LABEL}\`, format: \`${FORMAT}\`)
   - [ ] **Research as one expedition instead** (skip decomposition)
   ```

The narrow branch is unchanged — it has no Sub-topics section and no escape hatch.

- [ ] **Step 4.2: Smoke-test the dual-checkbox rendering with a stubbed `gh`.**

```bash
mkdir -p /tmp/scout-stub
cat > /tmp/scout-stub/gh <<'EOF'
#!/bin/sh
shift 2
while [ "$1" != "--body" ]; do shift; done; shift
printf '%s\n' "$1"
EOF
chmod +x /tmp/scout-stub/gh

PATH="/tmp/scout-stub:$PATH" \
ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=test/test \
DEPTH=deep DEPTH_LABEL=expedition FORMAT=auto \
SHARPENED_TOPIC="$(printf 'Test paragraph.\n\n```scout-subtopics\n- [ ] (survey) **Angle A** — first.\n- [ ] (recon) **Angle B** — second.\n```\n')" \
bash scripts/issue-comment.sh > /tmp/comment.out

grep -q '### Sub-topics' /tmp/comment.out && echo OK1 || echo FAIL1
grep -q '### Go' /tmp/comment.out && echo OK2 || echo FAIL2
grep -q '\*\*Start research\*\*' /tmp/comment.out && echo OK3 || echo FAIL3
grep -q '\*\*Research as one expedition instead\*\*' /tmp/comment.out && echo OK4 || echo FAIL4
grep -q 'informational for now' /tmp/comment.out && echo FAIL5 || echo OK5
grep -q 'Tick the ones to research' /tmp/comment.out && echo OK6 || echo FAIL6

# Narrow case unchanged
PATH="/tmp/scout-stub:$PATH" \
ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=test/test \
DEPTH=standard DEPTH_LABEL=survey FORMAT=auto \
SHARPENED_TOPIC="Plain narrow topic with no subtopics block." \
bash scripts/issue-comment.sh > /tmp/comment2.out

grep -q '### Sub-topics' /tmp/comment2.out && echo FAIL7 || echo OK7
grep -q 'Research as one expedition instead' /tmp/comment2.out && echo FAIL8 || echo OK8
```

Expected: `OK1 OK2 OK3 OK4 OK5 OK6 OK7 OK8`.

- [ ] **Step 4.3: Commit.**

```bash
git add scripts/issue-comment.sh
git commit -m "feat(comment): add escape-hatch checkbox + final disclaimer"
```

### Task 4b: Preserve sub-topics across re-sharpen

**Files:**
- Modify: `scout/.github/workflows/research.yml` (resharpen-on-comment job)
- Modify: `scout/scripts/sharpen.sh`
- Modify: `scout/skills/scout/sharpen.md`

When the user replies to the bot comment asking for revision (e.g. "merge angles 2 and 3"), the `resharpen-on-comment` job currently extracts only the paragraph (`PREVIOUS_SHARPENED`) from the prior bot comment's `scout-topic` block. After Stage 1, the prior sub-topics live in the `### Sub-topics` markdown section that sits OUTSIDE the `scout-topic` block — so they're invisible to the re-sharpen pass. Result: feedback like "merge angles 2 and 3" is meaningless because the sharpener doesn't see what 2 and 3 were.

This task harvests the prior sub-topics too and feeds them to the sharpener as a labeled input.

- [ ] **Step 4b.1: Update `sharpen.sh` to forward `PREVIOUS_SUB_TOPICS` env into the Claude prompt.**

In `scripts/sharpen.sh`, after the existing `if [ -n "${USER_FEEDBACK:-}" ]` block, add:

```bash
if [ -n "${PREVIOUS_SUB_TOPICS:-}" ]; then
  input+="
Previous sub-topics:
${PREVIOUS_SUB_TOPICS}"
fi
```

Update the file's header comment to list `PREVIOUS_SUB_TOPICS` as an optional env. The variable holds the verbatim content of the prior `### Sub-topics` section (including the `- [ ]` checkbox lines), without the heading itself.

- [ ] **Step 4b.2: Update `skills/scout/sharpen.md` Rule 7 (re-sharpen rule) to use the new input.**

Find the existing Rule 7 in `skills/scout/sharpen.md` (it currently says: *"On a re-sharpen: treat `User feedback to incorporate` as a hard constraint. Take the previous sharpened proposal, apply the feedback as a delta, output the revised version. Don't drift away from the user's original intent."*).

Append:

> **Sub-topic continuity on re-sharpen.** When `Previous sub-topics:` is present in the input, treat the listed sub-topics as the working set. Apply the user's feedback as a delta to that set: merge, drop, reorder, retitle, or change `(depth)` per the feedback's intent. If the feedback is paragraph-only (no sub-topic guidance), preserve the prior sub-topic list unchanged in your output's `scout-subtopics` block. Only re-decide the multi-angled judgment from scratch if the user explicitly asks ("decompose differently", "treat as one topic", etc.).

- [ ] **Step 4b.3: Update the `resharpen-on-comment` job in `.github/workflows/research.yml`.**

The job currently extracts `PREVIOUS_SHARPENED` via:

```bash
PREVIOUS_SHARPENED="$(
  gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" \
      --json comments \
      --jq '[.comments[] | select(.author.login == "github-actions[bot]")] | last | .body' \
  | awk '
      /^```scout-topic[[:space:]]*$/ { in_block=1; next }
      /^```[[:space:]]*$/ && in_block { exit }
      in_block { print }
    '
)"
```

Add a parallel extraction for `PREVIOUS_SUB_TOPICS` from the `### Sub-topics` markdown section of the same comment body. Capture the comment body once into a variable to avoid two `gh` calls:

```bash
PREVIOUS_BODY="$(gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" \
    --json comments \
    --jq '[.comments[] | select(.author.login == "github-actions[bot]")] | last | .body')"

PREVIOUS_SHARPENED="$(printf '%s' "$PREVIOUS_BODY" | awk '
  /^```scout-topic[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"

PREVIOUS_SUB_TOPICS="$(printf '%s' "$PREVIOUS_BODY" | awk '
  /^### Sub-topics[[:space:]]*$/ { in_section=1; next }
  /^### / && in_section { exit }
  in_section { print }
' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"
```

Then add `PREVIOUS_SUB_TOPICS="$PREVIOUS_SUB_TOPICS"` to the env block of the `bash scripts/sharpen.sh` invocation that follows.

`PREVIOUS_SUB_TOPICS` will be empty for narrow topics (no `### Sub-topics` section in the prior comment), and the new `sharpen.md` rule degrades gracefully when the input is absent.

- [ ] **Step 4b.4: Smoke-test the resharpen extraction.**

Stage a fake bot-comment body that contains both a `scout-topic` block and a `### Sub-topics` section, and verify both extractions yield the expected content:

```bash
BODY="$(printf '### Sharpened proposal\n\n> Para.\n\n<!-- scout-topic-start -->\n```scout-topic\nPara.\n```\n<!-- scout-topic-end -->\n\nDisclaimer.\n\n### Sub-topics\n\n- [ ] (survey) **A** — first.\n- [ ] (recon) **B** — second.\n\n### Go\n\n- [ ] **Start research**\n')"

PREV_TOPIC="$(printf '%s' "$BODY" | awk '/^```scout-topic[[:space:]]*$/ { i=1; next } /^```[[:space:]]*$/ && i { exit } i { print }')"
PREV_SUBS="$(printf '%s' "$BODY" | awk '/^### Sub-topics[[:space:]]*$/ { i=1; next } /^### / && i { exit } i { print }' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"

[ "$PREV_TOPIC" = "Para." ] && echo OK1 || echo FAIL1
echo "$PREV_SUBS" | grep -q '\[ \] (survey) \*\*A\*\*' && echo OK2 || echo FAIL2
echo "$PREV_SUBS" | grep -q '\[ \] (recon) \*\*B\*\*' && echo OK3 || echo FAIL3
echo "$PREV_SUBS" | grep -q 'Start research' && echo FAIL4 || echo OK4
```

Expected: `OK1 OK2 OK3 OK4`. (OK4 confirms the `### Go` boundary stops the extractor before the Start checkbox is included.)

- [ ] **Step 4b.5: Commit.**

```bash
git add scripts/sharpen.sh \
        skills/scout/sharpen.md \
        .github/workflows/research.yml
git commit -m "feat(resharpen): preserve sub-topics across user re-sharpen feedback"
```

### Task 5: Add `synthesis.md` skill

**Files:**
- Create: `scout/skills/scout/synthesis.md`

- [ ] **Step 5.1: Create the synthesis skill.**

```bash
cat > skills/scout/synthesis.md <<'EOF'
---
name: synthesis
description: Synthesise an expedition overview from N child research artifacts into a parent index. Invoked by scripts/run-decompose.sh after the children loop terminates.
---

# Synthesise an expedition overview

You receive the parent topic, a list of child sub-topics with their results, and write the parent `index.md`. The parent has two parts: synthesis prose at the top, an auto-generated children index below.

## Inputs

```
PARENT_TOPIC: <sharpened topic statement>
PARENT_DIR:   <absolute path to atlas/research/<DATE>-<slug>/>
CHILDREN:     <JSON array of {slug, title, depth, status, summary}>
DATE:         <YYYY-MM-DD>
FORMAT:       <md | html | auto>
SUCCESS_COUNT: <int — children with non-placeholder index.md>
```

`CHILDREN[i].summary` is pulled from each child's frontmatter. For failed children, `status: failed` and `summary` is the failure reason.

## Rules

1. **Honesty about gaps.** If a child failed or was skipped, *say so* in the synthesis prose. Do not paper over missing angles. Sentence template: "The <title> angle was not researched in this run (reason: <failure_reason>)."

2. **Cross-cutting only.** Don't re-summarise each child individually — the auto-generated index below the synthesis already lists each child's title and summary. The synthesis must add value beyond the sum: themes, contradictions, dependencies between angles, a unified recommendation, open questions left after all children ran.

3. **Citation discipline.** Inherits the Scout citation rule (`scout/CLAUDE.md`): every factual claim, quote, number, or summary line MUST carry its source URL inline. When citing across children, link to the child's URL using a relative link like `<child-slug>/#section`. When citing a fact from a child, copy the original source URL (don't reference the child as the source — the child cited the original).

4. **Length.** 200–600 words for the synthesis prose. No filler.

5. **No conclusion paragraph.** End on the sharpest open question or the strongest recommendation, not "in conclusion."

## Output

Write the parent `index.md` (or `index.html` if FORMAT=html) directly to `PARENT_DIR/index.md`. Do NOT print to stdout.

The file structure must be:

```yaml
---
layout: expedition
title: <inferred title>
date: <DATE>
topic: <PARENT_TOPIC>
format: <FORMAT>
synthesis: true
citations: <sum of CHILDREN[i].citations across status:success>
reading_time_min: <sum across status:success>
children:
  - slug: <child slug>
    title: <child title>
    depth: <recon|survey|expedition>
    status: <success|failed>
    summary: <copied from child frontmatter or failure_reason>
    citations: <int>           # only when success
    reading_time_min: <int>    # only when success
---

<synthesis prose, 200-600 words, with inline `[[n]](url)` citations>
```

The Atlas `expedition` layout renders the `children` frontmatter as a card grid below the synthesis — you do NOT need to list children in the body. Only write the synthesis prose.

If SUCCESS_COUNT < 2, set `synthesis: false` and write a one-sentence body ("Synthesis skipped — only <SUCCESS_COUNT> sub-topic(s) produced output. See child page(s) below.") without citations. The layout will still render the children grid.
EOF
```

- [ ] **Step 5.2: Commit.**

```bash
git add skills/scout/synthesis.md
git commit -m "feat(skill): add synthesis instructions for expedition overview pass"
```

### Task 6: Implement `run-decompose.sh` — child loop and resumability

**Files:**
- Create: `scout/scripts/run-decompose.sh`
- Create: `scout/tests/test_run_decompose_resumability.sh`

`run-decompose.sh` is the parent orchestrator. This task builds the skeleton + child loop + resumability check; subsequent tasks add timeout, synthesis, manifest, and failure-placeholder behavior.

- [ ] **Step 6.1: Write the resumability test (using a stub `run.sh`).**

```bash
cat > tests/test_run_decompose_resumability.sh <<'EOF'
#!/usr/bin/env bash
# Verifies run-decompose.sh skips children with an existing non-placeholder
# index.{md,html} and re-runs failure placeholders + missing children.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/run-decompose.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/atlas-checkout/research"
  # stub run.sh: marks the RESEARCH_DIR with a sentinel file and writes
  # a minimal successful index.md.
  cat > "$tmp/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub run.sh invoked: TOPIC=$TOPIC DEPTH=$DEPTH" >> "$RUN_LOG"
mkdir -p "$RESEARCH_DIR"
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: $TOPIC
status: success
citations: 5
reading_time_min: 2
---
stub body
MD
STUB
  chmod +x "$tmp/scout/scripts/run.sh"
  # Stub claude (used by synthesis pass; we won't reach it in resumability test
  # because we'll force <2 successes after the loop or pre-create successes.)
  cat > "$tmp/scout/scripts/claude-stub.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$tmp/scout/scripts/claude-stub.sh"
  echo "$tmp"
}

# --- Case A: fresh run, all 3 children invoked ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true\nC|standard|reasonC|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 3 ] && pass "fresh run: all 3 children invoked" \
                   || fail "fresh run: expected 3 invocations, got $count"

# --- Case B: pre-existing success at child A — only B and C re-run ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"
mkdir -p "$TMP/atlas-checkout/research/2026-04-26-test/a"
cat > "$TMP/atlas-checkout/research/2026-04-26-test/a/index.md" <<MD
---
title: A
status: success
---
already done
MD

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true\nC|standard|reasonC|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 2 ] && pass "resume: skips A, runs B+C" \
                   || fail "resume: expected 2 invocations, got $count"

# --- Case C: pre-existing failed placeholder at A — A IS re-run ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"
mkdir -p "$TMP/atlas-checkout/research/2026-04-26-test/a"
cat > "$TMP/atlas-checkout/research/2026-04-26-test/a/index.md" <<MD
---
title: A
status: failed
failure_reason: timeout
---
placeholder
MD

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 2 ] && pass "resume-failed: re-runs failed A + B" \
                   || fail "resume-failed: expected 2 invocations, got $count"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_run_decompose_resumability.sh
```

- [ ] **Step 6.2: Run — expect failure (script doesn't exist yet).**

```bash
bash tests/test_run_decompose_resumability.sh
```

Expected: `bash: scripts/run-decompose.sh: No such file or directory` and FAIL on every assertion.

- [ ] **Step 6.3: Implement `run-decompose.sh` (skeleton + child loop only).**

```bash
cat > scripts/run-decompose.sh <<'EOF'
#!/usr/bin/env bash
# Parent orchestrator for decomposed expeditions. Iterates over user-ticked
# sub-topics, invoking scripts/run.sh per child. Writes parent index.md via
# a synthesis pass when ≥2 children succeed.
#
# Required env: PARENT_DIR, PARENT_TOPIC, PARENT_FORMAT, DATE, SUB_TOPICS_TSV
# Optional env: SCOUT_DIR (defaults to script's parent), SCOUT_MAX_CHILDREN
#               (default 8), SCOUT_DECOMPOSE_SOFT_TIMEOUT (4h),
#               SCOUT_DECOMPOSE_HARD_TIMEOUT (4h20m), SCOUT_SKIP_SYNTHESIS
#               (test hook), RUN_LOG (test hook to record invocations).
#
# SUB_TOPICS_TSV is a newline-separated list of `title|depth|rationale|checked`
# entries (the same shape parse_sub_topics writes to the SUB_TOPICS array).

set -euo pipefail

: "${PARENT_DIR:?PARENT_DIR is required}"
: "${PARENT_TOPIC:?PARENT_TOPIC is required}"
: "${PARENT_FORMAT:=auto}"
: "${DATE:?DATE is required}"
: "${SUB_TOPICS_TSV:?SUB_TOPICS_TSV is required}"
: "${SCOUT_MAX_CHILDREN:=8}"
: "${SCOUT_DECOMPOSE_SOFT_TIMEOUT:=14400}"   # seconds, 4h
: "${SCOUT_DECOMPOSE_HARD_TIMEOUT:=15600}"   # seconds, 4h20m

SCOUT_DIR="${SCOUT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
mkdir -p "$PARENT_DIR"

# Slugify (uses existing scripts/slug.sh if available, else simple version).
if [ -f "$SCOUT_DIR/scripts/slug.sh" ]; then
  source "$SCOUT_DIR/scripts/slug.sh"
fi
_simple_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-60
}
_slugify_or_simple() {
  if declare -F slugify >/dev/null 2>&1; then slugify "$1"
  else _simple_slug "$1"
  fi
}

# Frontmatter helper: extracts a field's value from an index.md file.
_frontmatter_field() {
  local file="$1" field="$2"
  awk -v f="$field" '
    /^---[[:space:]]*$/ { in_fm = !in_fm; next }
    in_fm && $0 ~ "^"f":" { sub("^"f":[[:space:]]*", ""); print; exit }
  ' "$file"
}

# Returns 0 if child has a successful (non-placeholder) index.{md,html}.
_child_is_success() {
  local dir="$1"
  local file
  for file in "$dir/index.md" "$dir/index.html"; do
    [ -f "$file" ] || continue
    local status
    status="$(_frontmatter_field "$file" status)"
    [ "$status" = "failed" ] && return 1
    return 0
  done
  return 1
}

# Write a failure placeholder index.md for a child.
_write_placeholder() {
  local dir="$1" depth="$2" reason="$3"
  mkdir -p "$dir"
  cat > "$dir/index.md" <<MD
---
layout: research
title: $(basename "$dir")
status: failed
failure_reason: $reason
attempted_at: $(date -u +%FT%TZ)
depth: $depth
---

Research failed: $reason
MD
}

# --- Main loop ----------------------------------------------------------------

START_TS=$(date +%s)
PARENT_FORMAT_INTERNAL="$PARENT_FORMAT"

# Truncate at SCOUT_MAX_CHILDREN.
mapfile -t CHILDREN <<< "$(printf '%s\n' "$SUB_TOPICS_TSV" | grep '|true$' | head -n "$SCOUT_MAX_CHILDREN")"

manifest_path="$PARENT_DIR/manifest.json"
echo "[" > "$manifest_path.tmp"
manifest_first=1

for entry in "${CHILDREN[@]}"; do
  [ -n "$entry" ] || continue
  IFS='|' read -r ctitle cdepth crationale cchecked <<< "$entry"
  cslug="$(_slugify_or_simple "$ctitle")"
  child_dir="$PARENT_DIR/$cslug"
  child_status="unknown"
  child_start=$(date +%s)

  if _child_is_success "$child_dir"; then
    echo "[run-decompose] skip (already success): $cslug" >&2
    child_status="skipped_success"
  else
    elapsed=$(( $(date +%s) - START_TS ))
    if [ "$elapsed" -ge "$SCOUT_DECOMPOSE_SOFT_TIMEOUT" ]; then
      echo "[run-decompose] soft timeout reached, skipping: $cslug" >&2
      _write_placeholder "$child_dir" "$cdepth" "soft timeout reached before start"
      child_status="skipped_soft_timeout"
    else
      remaining=$(( SCOUT_DECOMPOSE_HARD_TIMEOUT - elapsed ))
      [ "$remaining" -lt 60 ] && remaining=60
      echo "[run-decompose] running child $cslug (depth=$cdepth, remaining=${remaining}s)" >&2
      rm -rf "$child_dir"
      mkdir -p "$child_dir"
      set +e
      env TOPIC="$ctitle" RAW_TOPIC="$ctitle" DEPTH="$cdepth" \
          FORMAT="$PARENT_FORMAT_INTERNAL" RESEARCH_DIR="$child_dir" \
          ATLAS_REPO="${ATLAS_REPO:-}" \
          ${RUN_LOG:+RUN_LOG="$RUN_LOG"} \
          timeout "${remaining}s" bash "$SCOUT_DIR/scripts/run.sh"
      rc=$?
      set -e
      if [ "$rc" -eq 0 ] && _child_is_success "$child_dir"; then
        child_status="success"
      elif [ "$rc" -eq 124 ]; then
        _write_placeholder "$child_dir" "$cdepth" "hard timeout"
        child_status="failed_hard_timeout"
      else
        _write_placeholder "$child_dir" "$cdepth" "child run.sh exit $rc"
        child_status="failed"
      fi
    fi
  fi

  # Append to manifest.
  child_end=$(date +%s)
  if [ "$manifest_first" -eq 1 ]; then manifest_first=0; else echo "," >> "$manifest_path.tmp"; fi
  printf '  {"slug":"%s","title":"%s","depth":"%s","status":"%s","start":%d,"end":%d}' \
    "$cslug" "$(printf '%s' "$ctitle" | sed 's/"/\\"/g')" "$cdepth" \
    "$child_status" "$child_start" "$child_end" >> "$manifest_path.tmp"
done

echo >> "$manifest_path.tmp"
echo "]" >> "$manifest_path.tmp"
mv "$manifest_path.tmp" "$manifest_path"

# --- Synthesis pass -----------------------------------------------------------

if [ "${SCOUT_SKIP_SYNTHESIS:-0}" = "1" ]; then
  exit 0
fi

# Synthesis is wired in Task 8. For now exit cleanly so the resumability
# test passes (it sets SCOUT_SKIP_SYNTHESIS=1 explicitly).
exit 0
EOF
chmod +x scripts/run-decompose.sh
```

- [ ] **Step 6.4: Run the resumability tests — expect all pass.**

```bash
bash tests/test_run_decompose_resumability.sh
```

Expected: three PASS lines, no FAIL lines.

- [ ] **Step 6.5: Commit.**

```bash
git add scripts/run-decompose.sh tests/test_run_decompose_resumability.sh
git commit -m "feat(decompose): child loop with resumability + manifest"
```

### Task 7: Soft + hard timeout handling

**Files:**
- Create: `scout/tests/test_run_decompose_timeout.sh`

The behavior is already implemented in Task 6 — this task locks it in with tests.

- [ ] **Step 7.1: Write the timeout tests.**

```bash
cat > tests/test_run_decompose_timeout.sh <<'EOF'
#!/usr/bin/env bash
# Tests soft + hard timeout in run-decompose.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/atlas-checkout"
  cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$tmp/scout/scripts/"
  cp "$REPO_ROOT/scripts/run-decompose.sh"   "$tmp/scout/scripts/"
  echo "$tmp"
}

# --- Soft timeout: stub run.sh sleeps 3s; soft timeout = 2s; second child
#                  is skipped with a placeholder. ---
TMP=$(setup)
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
sleep 3
cat > "$RESEARCH_DIR/index.md" <<MD
---
status: success
---
done
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true\nB|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_DECOMPOSE_SOFT_TIMEOUT=2 \
    SCOUT_DECOMPOSE_HARD_TIMEOUT=10 \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

# A should be successful, B should be a soft-timeout placeholder.
[ -f "$TMP/atlas-checkout/p/a/index.md" ] && \
  grep -q 'status: success' "$TMP/atlas-checkout/p/a/index.md" && \
  pass "soft: A succeeded" || fail "soft: A missing or not success"
[ -f "$TMP/atlas-checkout/p/b/index.md" ] && \
  grep -q 'failure_reason: soft timeout reached before start' "$TMP/atlas-checkout/p/b/index.md" && \
  pass "soft: B placeholder" || fail "soft: B not a soft-timeout placeholder"

# --- Hard timeout: stub sleeps 5s; hard cap forces remaining=1s, kills child. ---
TMP=$(setup)
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
sleep 5
cat > "$RESEARCH_DIR/index.md" <<MD
---
status: success
---
done
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_DECOMPOSE_SOFT_TIMEOUT=3600 \
    SCOUT_DECOMPOSE_HARD_TIMEOUT=2 \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

[ -f "$TMP/atlas-checkout/p/a/index.md" ] && \
  grep -q 'failure_reason: hard timeout' "$TMP/atlas-checkout/p/a/index.md" && \
  pass "hard: A killed" || fail "hard: A not a hard-timeout placeholder"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_run_decompose_timeout.sh
```

- [ ] **Step 7.2: Run — expect all pass.**

```bash
bash tests/test_run_decompose_timeout.sh
```

Expected: three PASS lines.

- [ ] **Step 7.3: Commit.**

```bash
git add tests/test_run_decompose_timeout.sh
git commit -m "test(decompose): soft + hard timeout coverage"
```

### Task 8: Synthesis pass + ≥2 success gate

**Files:**
- Modify: `scout/scripts/run-decompose.sh`
- Create: `scout/tests/test_run_decompose_synthesis_gate.sh`

- [ ] **Step 8.1: Write the synthesis-gate test.**

```bash
cat > tests/test_run_decompose_synthesis_gate.sh <<'EOF'
#!/usr/bin/env bash
# Verifies synthesis pass invocation:
#   0 successes → no synthesis call
#   1 success   → no synthesis call
#   2+ successes → exactly one synthesis call

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

setup_with_n_successes() {
  local n="$1"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/atlas-checkout"
  cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$tmp/scout/scripts/"
  cp "$REPO_ROOT/scripts/run-decompose.sh"   "$tmp/scout/scripts/"

  # run.sh stub: writes success for first $n calls, then failure.
  cat > "$tmp/scout/scripts/run.sh" <<STUB
#!/usr/bin/env bash
COUNTER_FILE="\$SCOUT_DIR/scripts/.counter"
[ -f "\$COUNTER_FILE" ] || echo 0 > "\$COUNTER_FILE"
i=\$(cat "\$COUNTER_FILE")
i=\$((i+1)); echo \$i > "\$COUNTER_FILE"
mkdir -p "\$RESEARCH_DIR"
if [ "\$i" -le "$n" ]; then
  cat > "\$RESEARCH_DIR/index.md" <<MD
---
title: stub
status: success
citations: 5
reading_time_min: 2
---
ok
MD
else
  exit 1
fi
STUB
  chmod +x "$tmp/scout/scripts/run.sh"

  # Stub claude as a synthesis-call recorder.
  cat > "$tmp/scout/bin-claude" <<'STUB'
#!/usr/bin/env bash
echo "synthesis invoked" >> "$SYNTHESIS_LOG"
# Synthesis is expected to write parent index.md. Emulate that.
PARENT_DIR_FROM_PROMPT="$(grep -oE 'PARENT_DIR: [^ ]+' <<< "$@" | head -1 | awk '{print $2}')"
[ -n "$PARENT_DIR_FROM_PROMPT" ] && \
  cat > "$PARENT_DIR_FROM_PROMPT/index.md" <<MD
---
layout: expedition
title: synthesis stub
synthesis: true
---
synthesised
MD
echo '{"total_cost_usd":0.01,"duration_ms":1000,"result":"ok"}'
STUB
  chmod +x "$tmp/scout/bin-claude"
  echo "$tmp"
}

run_case() {
  local n="$1" expected_invocations="$2" label="$3"
  local tmp; tmp=$(setup_with_n_successes "$n")
  local synthesis_log="$tmp/synthesis.log"
  touch "$synthesis_log"

  PATH="$tmp:$PATH" \
    env PARENT_DIR="$tmp/atlas-checkout/p" \
        PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
        SUB_TOPICS_TSV=$'A|standard||true\nB|standard||true\nC|standard||true' \
        SCOUT_DIR="$tmp/scout" \
        SYNTHESIS_LOG="$synthesis_log" \
        bash "$tmp/scout/scripts/run-decompose.sh" >/dev/null 2>&1

  local count
  count=$(wc -l < "$synthesis_log" | tr -d ' ')
  [ "$count" -eq "$expected_invocations" ] && pass "$label" \
      || fail "$label: expected $expected_invocations, got $count"
}

# Override `claude` in PATH per case via setup's bin-claude → claude symlink.
# Simpler: tests above invoke "claude" via PATH. Each case symlinks bin-claude.
# Adjust setup_with_n_successes to symlink:
#   ln -s bin-claude $tmp/claude
# (The setup function above doesn't yet — fix here.)
# Trick: the synthesis call in run-decompose.sh shells out to `claude` directly.
# We rename bin-claude to `claude` in $tmp, and put $tmp first in PATH.
mv_claude() {
  mv "$1/bin-claude" "$1/claude"
}

# Patch run_case to call mv_claude before invoking.
# (We re-run the cases inline here.)

for n in 0 1 2 3; do
  tmp=$(setup_with_n_successes "$n")
  mv_claude "$tmp"
  synthesis_log="$tmp/synthesis.log"
  touch "$synthesis_log"
  PATH="$tmp:$PATH" \
    env PARENT_DIR="$tmp/atlas-checkout/p" \
        PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
        SUB_TOPICS_TSV=$'A|standard||true\nB|standard||true\nC|standard||true' \
        SCOUT_DIR="$tmp/scout" \
        SYNTHESIS_LOG="$synthesis_log" \
        bash "$tmp/scout/scripts/run-decompose.sh" >/dev/null 2>&1 || true
  count=$(wc -l < "$synthesis_log" | tr -d ' ')
  expected=0; [ "$n" -ge 2 ] && expected=1
  [ "$count" -eq "$expected" ] && pass "n=$n: synthesis=$expected" \
                              || fail "n=$n: expected synthesis=$expected, got $count"
done

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_run_decompose_synthesis_gate.sh
```

- [ ] **Step 8.2: Run — expect failure (synthesis not yet wired).**

```bash
bash tests/test_run_decompose_synthesis_gate.sh
```

Expected: cases n=2 and n=3 fail (`expected synthesis=1, got 0`); n=0 and n=1 pass coincidentally.

- [ ] **Step 8.3: Wire the synthesis pass.**

Replace the placeholder synthesis block at the bottom of `scripts/run-decompose.sh` (the section starting `# --- Synthesis pass ---`) with:

```bash
# --- Synthesis pass -----------------------------------------------------------

if [ "${SCOUT_SKIP_SYNTHESIS:-0}" = "1" ]; then
  exit 0
fi

# Count successful (non-placeholder) children.
SUCCESS_COUNT=0
CHILDREN_JSON='['
first=1
for entry in "${CHILDREN[@]}"; do
  [ -n "$entry" ] || continue
  IFS='|' read -r ctitle cdepth crationale cchecked <<< "$entry"
  cslug="$(_slugify_or_simple "$ctitle")"
  child_dir="$PARENT_DIR/$cslug"
  status="failed"
  summary=""
  citations=0
  reading=0
  if _child_is_success "$child_dir"; then
    status="success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    summary="$(_frontmatter_field "$child_dir/index.md" summary)"
    [ -z "$summary" ] && summary="$(_frontmatter_field "$child_dir/index.md" title)"
    citations="$(_frontmatter_field "$child_dir/index.md" citations)"
    reading="$(_frontmatter_field "$child_dir/index.md" reading_time_min)"
    [ -z "$citations" ] && citations=0
    [ -z "$reading" ] && reading=0
  elif [ -f "$child_dir/index.md" ]; then
    summary="$(_frontmatter_field "$child_dir/index.md" failure_reason)"
  fi
  [ "$first" -eq 1 ] && first=0 || CHILDREN_JSON+=","
  CHILDREN_JSON+=$(printf '\n  {"slug":"%s","title":"%s","depth":"%s","status":"%s","summary":"%s","citations":%s,"reading_time_min":%s}' \
    "$cslug" \
    "$(printf '%s' "$ctitle" | sed 's/"/\\"/g')" \
    "$cdepth" "$status" \
    "$(printf '%s' "$summary" | sed 's/"/\\"/g')" \
    "$citations" "$reading")
done
CHILDREN_JSON+=$'\n]'

if [ "$SUCCESS_COUNT" -lt 2 ]; then
  # Auto-only parent index — no synthesis prose.
  cat > "$PARENT_DIR/index.md" <<MD
---
layout: expedition
title: $(basename "$PARENT_DIR")
date: $DATE
topic: $PARENT_TOPIC
format: $PARENT_FORMAT
synthesis: false
children: $CHILDREN_JSON
---

Synthesis skipped — only $SUCCESS_COUNT sub-topic(s) produced output. See child page(s) below.
MD
  exit 0
fi

# Synthesis pass: invoke Claude with skills/scout/synthesis.md.
SKILL_CONTENT="$(cat "$SCOUT_DIR/skills/scout/synthesis.md")"
PROMPT="$(cat <<EOF
PARENT_TOPIC: ${PARENT_TOPIC}
PARENT_DIR: ${PARENT_DIR}
DATE: ${DATE}
FORMAT: ${PARENT_FORMAT}
SUCCESS_COUNT: ${SUCCESS_COUNT}
CHILDREN: ${CHILDREN_JSON}

Use the synthesis skill. Write the parent index.md to PARENT_DIR/index.md.
EOF
)"

claude --dangerously-skip-permissions \
       --print \
       --output-format json \
       --append-system-prompt "$SKILL_CONTENT" \
       "$PROMPT" > "$PARENT_DIR/.synthesis-result.json" || true

rm -f "$PARENT_DIR/.synthesis-result.json"
```

- [ ] **Step 8.4: Run the synthesis tests — expect all pass.**

```bash
bash tests/test_run_decompose_synthesis_gate.sh
```

Expected: four PASS lines (n=0,1,2,3).

- [ ] **Step 8.5: Run all decompose tests together to confirm no regression.**

```bash
bash tests/test_run_decompose_resumability.sh && \
bash tests/test_run_decompose_timeout.sh && \
bash tests/test_run_decompose_synthesis_gate.sh
```

Expected: all pass.

- [ ] **Step 8.6: Commit.**

```bash
git add scripts/run-decompose.sh tests/test_run_decompose_synthesis_gate.sh
git commit -m "feat(decompose): synthesis pass with >=2 success gate"
```

### Task 9: Failure placeholder shape — frontmatter contract test

**Files:**
- Create: `scout/tests/test_failure_placeholder.sh`

- [ ] **Step 9.1: Write the placeholder shape test.**

```bash
cat > tests/test_failure_placeholder.sh <<'EOF'
#!/usr/bin/env bash
# Verifies failure placeholders written by run-decompose.sh have the required
# frontmatter keys: status: failed, failure_reason, attempted_at, depth, layout: research.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMP=$(mktemp -d)
mkdir -p "$TMP/scout/scripts" "$TMP/atlas-checkout"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"

# Stub run.sh that always fails.
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh" >/dev/null 2>&1

f="$TMP/atlas-checkout/p/a/index.md"
[ -f "$f" ] && pass "placeholder file exists" || fail "no placeholder at $f"
grep -q '^layout: research' "$f"  && pass "layout: research"  || fail "missing layout: research"
grep -q '^status: failed'   "$f"  && pass "status: failed"    || fail "missing status: failed"
grep -q '^failure_reason: ' "$f"  && pass "failure_reason set" || fail "missing failure_reason"
grep -q '^attempted_at: '   "$f"  && pass "attempted_at set"  || fail "missing attempted_at"
grep -q '^depth: standard'  "$f"  && pass "depth recorded"    || fail "missing depth"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
EOF
chmod +x tests/test_failure_placeholder.sh
```

- [ ] **Step 9.2: Run — expect all pass.**

```bash
bash tests/test_failure_placeholder.sh
```

Expected: six PASS lines.

- [ ] **Step 9.3: Commit.**

```bash
git add tests/test_failure_placeholder.sh
git commit -m "test(decompose): placeholder frontmatter contract"
```

### Task 10: Wire `research-from-issue.sh` to branch on Sub-topics + Start choice

**Files:**
- Modify: `scout/scripts/research-from-issue.sh`

- [ ] **Step 10.1: Replace `research-from-issue.sh` with the branched version.**

```bash
cat > scripts/research-from-issue.sh <<'EOF'
#!/usr/bin/env bash
# Glue between the issue-event workflow and the research pipeline.
# Inspects the bot comment to decide between single-pass run.sh and
# decomposed run-decompose.sh.
#
# Required env: BOT_COMMENT_BODY, ISSUE_NUMBER, GH_TOKEN, GH_REPO.

set -euo pipefail

: "${BOT_COMMENT_BODY:?BOT_COMMENT_BODY is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GH_REPO:?GH_REPO is required}"

SCOUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCOUT_DIR/scripts/lib-issue-parse.sh"

# Topic — content of the scout-topic fenced block in the bot comment.
TOPIC="$(printf '%s' "$BOT_COMMENT_BODY" | awk '
  /^```scout-topic[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"

if [ -z "$TOPIC" ]; then
  echo "Error: could not extract scout-topic block from bot comment." >&2
  exit 1
fi

# Original issue body for raw topic + depth + format.
issue_body="$(gh issue view "$ISSUE_NUMBER" --repo "$GH_REPO" --json body --jq .body)"
parse_issue_body "$issue_body"

# Determine routing: decompose vs single-pass.
parse_start_choice "$BOT_COMMENT_BODY"
parse_sub_topics   "$BOT_COMMENT_BODY"

if [ "$START_CHOICE" = "decompose" ] && [ "${#SUB_TOPICS[@]}" -gt 0 ]; then
  echo "[research-from-issue] routing: decompose (${#SUB_TOPICS[@]} sub-topics)" >&2
  # Build SUB_TOPICS_TSV from the parsed array.
  SUB_TOPICS_TSV="$(printf '%s\n' "${SUB_TOPICS[@]}")"

  # Pre-create parent folder under atlas-checkout (run-decompose calls
  # run.sh per child which would re-clone — instead we clone once here).
  ATLAS_REPO="${ATLAS_REPO:-git@github.com:Laoujin/atlas.git}"
  ATLAS_DIR="$SCOUT_DIR/atlas-checkout"
  rm -rf "$ATLAS_DIR"
  git clone --depth=1 "$ATLAS_REPO" "$ATLAS_DIR"
  source "$SCOUT_DIR/scripts/slug.sh"
  DATE="$(date +%F)"
  PARENT_SLUG="$(slugify "$TOPIC")"
  n=2
  while [ -d "$ATLAS_DIR/research/${DATE}-${PARENT_SLUG}" ]; do
    PARENT_SLUG="$(slugify "$TOPIC")-${n}"
    n=$((n+1))
  done
  PARENT_DIR="$ATLAS_DIR/research/${DATE}-${PARENT_SLUG}"
  mkdir -p "$PARENT_DIR"

  export PARENT_DIR PARENT_TOPIC="$TOPIC" PARENT_FORMAT="$FORMAT" DATE
  export SUB_TOPICS_TSV ATLAS_REPO ISSUE_NUMBER GH_TOKEN GH_REPO
  exec bash "$SCOUT_DIR/scripts/run-decompose.sh"
fi

# Single-pass fallback (covers START_CHOICE=as_one and the "no Sub-topics
# present" case from before this feature shipped).
echo "[research-from-issue] routing: single-pass" >&2
[ -n "$RAW_TOPIC" ] || RAW_TOPIC="$TOPIC"
export TOPIC RAW_TOPIC DEPTH FORMAT ISSUE_NUMBER
exec bash "$SCOUT_DIR/scripts/run.sh"
EOF
chmod +x scripts/research-from-issue.sh
```

- [ ] **Step 10.2: Smoke-test the routing locally.**

```bash
mkdir -p /tmp/scout-stub-rfi
cat > /tmp/scout-stub-rfi/gh <<'EOF'
#!/bin/sh
# Stub gh: respond to "issue view --json body --jq .body" with a fixed body.
echo "### Topic
test
### Depth
expedition
### Format
auto"
EOF
chmod +x /tmp/scout-stub-rfi/gh

# Stub run-decompose and run to record which one fires.
cp scripts/run-decompose.sh /tmp/scout-stub-rfi/run-decompose-orig.sh
cat > scripts/run-decompose.sh <<'EOF'
#!/usr/bin/env bash
echo "DECOMPOSE FIRED" > /tmp/scout-rfi-out
EOF
chmod +x scripts/run-decompose.sh

cp scripts/run.sh /tmp/scout-stub-rfi/run-orig.sh
cat > scripts/run.sh <<'EOF'
#!/usr/bin/env bash
echo "SINGLEPASS FIRED" > /tmp/scout-rfi-out
EOF
chmod +x scripts/run.sh

# Decompose path
PATH="/tmp/scout-stub-rfi:$PATH" \
  BOT_COMMENT_BODY="$(printf '\n```scout-topic\nt\n```\n### Sub-topics\n- [x] (survey) **A** — r.\n- [x] (survey) **B** — r.\n### Go\n- [x] **Start research**\n- [ ] **Research as one expedition instead**\n')" \
  ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=t/t \
  bash scripts/research-from-issue.sh 2>/dev/null
grep -q DECOMPOSE /tmp/scout-rfi-out && echo OK1 || echo FAIL1

# As-one path
PATH="/tmp/scout-stub-rfi:$PATH" \
  BOT_COMMENT_BODY="$(printf '\n```scout-topic\nt\n```\n### Sub-topics\n- [x] (survey) **A** — r.\n### Go\n- [ ] **Start research**\n- [x] **Research as one expedition instead**\n')" \
  ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=t/t \
  bash scripts/research-from-issue.sh 2>/dev/null
grep -q SINGLEPASS /tmp/scout-rfi-out && echo OK2 || echo FAIL2

# Restore real scripts.
mv /tmp/scout-stub-rfi/run-decompose-orig.sh scripts/run-decompose.sh
mv /tmp/scout-stub-rfi/run-orig.sh scripts/run.sh
chmod +x scripts/run-decompose.sh scripts/run.sh
```

Expected: `OK1 OK2`.

- [ ] **Step 10.3: Commit.**

```bash
git add scripts/research-from-issue.sh
git commit -m "feat(workflow): branch research entry on sub-topics + start choice"
```

### Task 11: Update workflow trigger to include "Research as one" tick

**Files:**
- Modify: `scout/.github/workflows/research.yml`

- [ ] **Step 11.1: Update the `research` job's `if:` condition.**

Locate lines 119–127 of `.github/workflows/research.yml` (the `research:` job's `if:` block) and replace the trailing two lines:

```yaml
      contains(github.event.changes.body.from, '- [ ] **Start research**') &&
      (contains(github.event.comment.body, '- [x] **Start research**') ||
       contains(github.event.comment.body, '- [X] **Start research**'))
```

with:

```yaml
      (contains(github.event.changes.body.from, '- [ ] **Start research**') ||
       contains(github.event.changes.body.from, '- [ ] **Research as one expedition instead**')) &&
      (contains(github.event.comment.body, '- [x] **Start research**') ||
       contains(github.event.comment.body, '- [X] **Start research**') ||
       contains(github.event.comment.body, '- [x] **Research as one expedition instead**') ||
       contains(github.event.comment.body, '- [X] **Research as one expedition instead**'))
```

The `from` clause matches when the previous comment state had EITHER unticked checkbox; the second clause matches the ticked state of either box.

- [ ] **Step 11.2: Lint the workflow YAML.**

```bash
# If actionlint is available; otherwise skip.
command -v actionlint && actionlint .github/workflows/research.yml
# As a minimal sanity check:
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/research.yml"))' && echo OK
```

Expected: `OK`. (No syntax errors.)

- [ ] **Step 11.3: Commit.**

```bash
git add .github/workflows/research.yml
git commit -m "feat(ci): trigger research job on either Start checkbox tick"
```

### Task 12: Soft-fail comment with failed-children list in `publish.sh`

**Files:**
- Modify: `scout/scripts/publish.sh`
- Modify: `scout/tests/test_publish.sh`

`run-decompose.sh` writes failure placeholders into the parent folder. `publish.sh` already supports a soft-fail path (via `SOFT_FAIL_LOG`); we extend it to scan the parent folder for `status: failed` children and append them to the soft-fail comment.

- [ ] **Step 12.1: Read the current `publish.sh` to find the soft-fail block.**

```bash
grep -n 'SOFT_FAIL_LOG\|soft-fail\|gh issue close' scripts/publish.sh
```

Note the line numbers for: (a) where the soft-fail comment body is constructed, (b) where `gh issue close` is called.

- [ ] **Step 12.2: Insert failed-children scan before the soft-fail comment construction.**

After the `SOFT_FAIL_LOG` line and before the soft-fail comment-body construction, add:

```bash
# Scan parent folder for failed children placeholders. If RESEARCH_DIR is the
# parent of an expedition (contains child folders with index.md), append a
# bullet list of failed children to the soft-fail log so the comment surfaces
# them and the issue stays open.
if [ -n "${RESEARCH_DIR:-}" ] && [ -d "$RESEARCH_DIR" ]; then
  while IFS= read -r child_index; do
    child_dir="$(dirname "$child_index")"
    [ "$child_dir" = "$RESEARCH_DIR" ] && continue   # parent itself
    if grep -q '^status: failed' "$child_index"; then
      reason="$(awk -F': ' '/^failure_reason:/ { sub(/^failure_reason:[[:space:]]*/, ""); print; exit }' "$child_index")"
      cslug="$(basename "$child_dir")"
      echo "- \`$cslug\`: $reason" >> "$SOFT_FAIL_LOG"
    fi
  done < <(find "$RESEARCH_DIR" -mindepth 2 -maxdepth 2 -name 'index.md' -o -name 'index.html')
fi
```

This appends one bullet per failed child to `SOFT_FAIL_LOG`. The existing soft-fail comment template will surface them; if any failed children are appended, `publish.sh`'s existing rule of "soft-fail log non-empty ⇒ keep issue open" already handles the rest.

- [ ] **Step 12.3: Add a mixed-success test case to `test_publish.sh`.**

Append to `tests/test_publish.sh` before its summary block:

```bash
# --- Mixed-success expedition: failed child placeholder makes issue stay open ---
TMP=$(setup_tmp)
mkdir -p "$TMP/atlas-checkout/_research/2026-04-23-test/a" \
         "$TMP/atlas-checkout/_research/2026-04-23-test/b"
cat > "$TMP/atlas-checkout/_research/2026-04-23-test/a/index.md" <<MD
---
status: success
title: A
---
ok
MD
cat > "$TMP/atlas-checkout/_research/2026-04-23-test/b/index.md" <<MD
---
status: failed
failure_reason: hard timeout
title: B
---
placeholder
MD
RESEARCH_DIR="$TMP/atlas-checkout/_research/2026-04-23-test" run_publish "$TMP"

# After this case, the soft-fail comment path should be taken and the issue
# left open. We can't truly inspect that here without gh, but we can verify
# the SOFT_FAIL_LOG mention in publish.log if your harness pipes it.
grep -q 'b.*hard timeout' "$TMP/publish.log" 2>/dev/null \
  && pass "publish: failed child surfaced in soft-fail" \
  || fail "publish: failed child not surfaced"
```

(Adjust `RESEARCH_DIR` and the test scaffold to match the actual signature of `run_publish` in your test harness — refer to lines 1–80 of the existing `test_publish.sh` for variable names and helper conventions.)

- [ ] **Step 12.4: Run the publish tests.**

```bash
bash tests/test_publish.sh
```

Expected: all PASS, including the new mixed-success case.

- [ ] **Step 12.5: Commit.**

```bash
git add scripts/publish.sh tests/test_publish.sh
git commit -m "feat(publish): list failed children in soft-fail comment"
```

### Stage 2 commit checkpoint

- [ ] **Step S2.C: Verify the full Scout test suite passes.**

```bash
for t in tests/test_*.sh; do echo "==> $t"; bash "$t" || break; done
```

Expected: every test file ends with `Passed: N, Failed: 0` and exits 0. (Snapshot tests skip cleanly with `SCOUT_SKIP_CLAUDE=1` if needed for headless runs.)

Stage 2 is now complete and on `main`. The pipeline can decompose, run children, partial-publish, and resume. Atlas still uses the existing `research` layout for everything (parent overview included) — the visible difference is purely in the parent's auto-generated body listing children.

---

## Stage 3 — Atlas L2 layout

**Outcome:** Parent expedition pages render with a dedicated `expedition` layout: distinct hero badge, optional synthesis prose, and a children-card grid with success and failed states. Atlas home grid shows expeditions with an "N angles" overlay.

(Working directory for this stage: `/mnt/c/Users/woute/Dropbox/Personal/Programming/UnixCode/projects/Scout+Atlas/atlas`.)

### Task 13: Create `_layouts/expedition.html`

**Files:**
- Create: `atlas/_layouts/expedition.html`

- [ ] **Step 13.1: Build the layout, mirroring `_layouts/research.html`.**

```bash
cat > _layouts/expedition.html <<'EOF'
---
---
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>{% if page.title %}{{ page.title }} — {% endif %}{{ site.title }}</title>
  <link rel="icon" type="image/png" href="{{ '/assets/icon.png' | relative_url }}">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,600&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="{{ '/assets/palettes/' | append: site.palette | append: '.css' | relative_url }}">
  <link rel="stylesheet" href="{{ '/assets/base.css' | relative_url }}">
  <link rel="stylesheet" href="{{ '/assets/research.css' | relative_url }}">
</head>
<body class="research-page expedition-page">
  <header class="research-hero">
    <a href="{{ '/' | relative_url }}" class="research-back">← {{ site.title }}</a>
    {% if page.title %}<h1>{{ page.title }}</h1>{% endif %}
    {% assign success_count = 0 %}
    {% assign failed_count = 0 %}
    {% for c in page.children %}
      {% if c.status == 'success' %}{% assign success_count = success_count | plus: 1 %}{% endif %}
      {% if c.status == 'failed' %}{% assign failed_count = failed_count | plus: 1 %}{% endif %}
    {% endfor %}
    <p class="research-meta">
      <span class="depth-badge depth-expedition">expedition</span>
      {% if page.format %}<span class="fmt-pill fmt-{{ page.format }}">.{{ page.format }}</span>{% endif %}
      {% if page.date %}<time>{{ page.date | date: "%Y-%m-%d" }}</time>{% endif %}
      <span>{{ page.children | size }} angles · {{ success_count }} succeeded{% if failed_count > 0 %} · {{ failed_count }} placeholders{% endif %}</span>
      {% if page.citations %}<span>{{ page.citations }} sources</span>{% endif %}
      {% if page.reading_time_min %}<span>~{{ page.reading_time_min }} min</span>{% endif %}
    </p>
    {% if page.topic %}<p class="research-topic">{{ page.topic }}</p>{% endif %}
  </header>
  <main class="research-main">
    {% if page.synthesis %}
      <section class="expedition-synthesis">
        {{ content }}
      </section>
    {% else %}
      <section class="expedition-synthesis expedition-synthesis-empty">
        {{ content }}
      </section>
    {% endif %}
    <section class="expedition-children">
      <h2>Sub-topics</h2>
      {% include research-children.html %}
    </section>
  </main>
  <footer class="research-footer">
    <p>Scout researches. Atlas remembers.</p>
  </footer>
  <script defer src="{{ '/assets/table-cards.js' | relative_url }}"></script>
</body>
</html>
EOF
```

- [ ] **Step 13.2: Commit.**

```bash
git add _layouts/expedition.html
git commit -m "feat(atlas): expedition layout for parent overview pages"
```

### Task 14: Create `_includes/research-children.html`

**Files:**
- Create: `atlas/_includes/research-children.html`

- [ ] **Step 14.1: Build the include.**

```bash
cat > _includes/research-children.html <<'EOF'
{%- comment -%}
Renders page.children as a card grid. Each child is one of:
  status: success → linked card (whole card is anchor)
  status: failed  → greyed-out card with failure_reason, no link
{%- endcomment -%}
<div class="children-grid">
  {% for c in page.children %}
    {% if c.status == 'success' %}
      <a class="child-card child-card-success" href="{{ c.slug | relative_url }}/">
        <div class="child-card-meta">
          <span class="depth-badge depth-{{ c.depth | replace: 'ceo', 'recon' | replace: 'standard', 'survey' | replace: 'deep', 'expedition' }}">{{ c.depth | replace: 'ceo', 'recon' | replace: 'standard', 'survey' | replace: 'deep', 'expedition' }}</span>
          {% if c.citations %}<span>{{ c.citations }} sources</span>{% endif %}
          {% if c.reading_time_min %}<span>~{{ c.reading_time_min }} min</span>{% endif %}
        </div>
        <h3 class="child-card-title">{{ c.title }}</h3>
        {% if c.summary %}<p class="child-card-summary">{{ c.summary }}</p>{% endif %}
      </a>
    {% else %}
      <div class="child-card child-card-failed" aria-disabled="true">
        <div class="child-card-meta">
          <span class="depth-badge depth-{{ c.depth | replace: 'ceo', 'recon' | replace: 'standard', 'survey' | replace: 'deep', 'expedition' }} depth-faded">{{ c.depth | replace: 'ceo', 'recon' | replace: 'standard', 'survey' | replace: 'deep', 'expedition' }}</span>
          <span class="failed-badge">failed</span>
        </div>
        <h3 class="child-card-title">{{ c.title }}</h3>
        {% if c.summary %}<p class="child-card-summary">Reason: {{ c.summary }}</p>{% endif %}
      </div>
    {% endif %}
  {% endfor %}
</div>
EOF
```

- [ ] **Step 14.2: Commit.**

```bash
git add _includes/research-children.html
git commit -m "feat(atlas): research-children include with success/failed states"
```

### Task 15: Add expedition badge + children-grid CSS

**Files:**
- Modify: `atlas/assets/research.css` (or whichever CSS the existing layout pulls in — confirm via `grep -l 'depth-badge' atlas/assets/`)

- [ ] **Step 15.1: Inspect existing depth-badge styles.**

```bash
grep -n '\.depth-badge\|\.depth-recon\|\.depth-survey\|\.depth-deep\|\.depth-expedition' assets/*.css
```

Note the location and existing structure. The existing palette likely has `--depth-recon`, `--depth-survey`, `--depth-deep` tokens.

- [ ] **Step 15.2: Append expedition + children-grid styles.**

Append to `assets/research.css`:

```css
/* Expedition layout — parent overview */
.expedition-page .depth-expedition {
  background: var(--expedition, var(--depth-deep, #4c1d95));
  color: #fff;
}
.expedition-synthesis { margin-block-end: 2.5rem; }
.expedition-synthesis-empty { color: var(--muted, #666); font-style: italic; }
.expedition-children h2 { margin-block-end: 1rem; }
.children-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 1rem;
}
.child-card {
  display: block;
  padding: 1rem;
  border: 1px solid var(--border, #ddd);
  border-radius: 8px;
  text-decoration: none;
  color: inherit;
  transition: transform 120ms ease, box-shadow 120ms ease;
}
.child-card-success:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
.child-card-failed { opacity: 0.55; cursor: not-allowed; }
.child-card-failed .failed-badge {
  background: #b91c1c; color: #fff; padding: 0.1rem 0.5rem; border-radius: 4px; font-size: 0.75rem;
}
.child-card-meta { display: flex; gap: 0.5rem; margin-block-end: 0.5rem; font-size: 0.85rem; }
.child-card-title { margin: 0 0 0.5rem; font-size: 1.1rem; }
.child-card-summary { margin: 0; color: var(--muted, #555); font-size: 0.95rem; }
.depth-faded { opacity: 0.6; }
```

- [ ] **Step 15.3: Commit.**

```bash
git add assets/research.css
git commit -m "feat(atlas): expedition badge + children-grid styles"
```

### Task 16: Add `--expedition` palette token

**Files:**
- Modify: every file in `atlas/assets/palettes/*.css`

- [ ] **Step 16.1: List palette files.**

```bash
ls assets/palettes/
```

- [ ] **Step 16.2: Add `--expedition` token to each palette.**

For each `assets/palettes/<palette>.css`, find the `:root` (or top-level CSS variable) block and add a line:

```css
  --expedition: #4c1d95;   /* deep purple — distinct from depth-deep */
```

(Pick a palette-appropriate hue per file; the value above is a sensible default.)

- [ ] **Step 16.3: Commit.**

```bash
git add assets/palettes/
git commit -m "feat(atlas): add --expedition palette token across themes"
```

### Task 17: Add expedition badge + "N angles" overlay to home cards

**Files:**
- Modify: `atlas/_includes/cards/v1.html` and any other home-grid card variants used by `_config.yml`'s `cards` setting.

- [ ] **Step 17.1: Identify which card variants are in active use.**

```bash
grep -n 'cards:' _config.yml
ls _includes/cards/
```

Read the variant currently configured (e.g. `v1.html`).

- [ ] **Step 17.2: For each in-use card variant, add the expedition treatment.**

Locate the depth badge / depth label rendering inside `_includes/cards/<vN>.html`. Add a conditional block for expedition pages:

```liquid
{% if include.page.children %}
  <span class="depth-badge depth-expedition">expedition</span>
  <span class="angles-overlay">{{ include.page.children | size }} angles</span>
{% else %}
  <!-- existing depth badge rendering -->
{% endif %}
```

The exact insertion point depends on the variant — preserve all existing card content, just gate the depth badge swap on `include.page.children` being non-empty.

- [ ] **Step 17.3: Add an `.angles-overlay` style.**

Append to `assets/research.css` (or the home-grid stylesheet):

```css
.angles-overlay {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
  background: var(--expedition, #4c1d95);
  color: #fff;
  padding: 0.15rem 0.5rem;
  border-radius: 4px;
  font-size: 0.75rem;
  font-weight: 600;
}
```

(Confirm card containers have `position: relative` already; add `position: relative` to the card class if not.)

- [ ] **Step 17.4: Commit.**

```bash
git add _includes/cards/ assets/research.css
git commit -m "feat(atlas): expedition badge + N-angles overlay on home cards"
```

### Task 18: Add preview fixtures

**Files:**
- Create: `atlas/_previews/expedition/index.html`
- Create: `atlas/_previews/expedition-partial/index.html`

- [ ] **Step 18.1: Create the full-success preview.**

```bash
mkdir -p _previews/expedition
cat > _previews/expedition/index.html <<'EOF'
---
layout: expedition
title: Development work on the go
date: 2026-04-26
topic: Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology.
format: auto
synthesis: true
citations: 87
reading_time_min: 42
children:
  - slug: slack-claude-code-remote-control
    title: Slack ↔ Claude Code remote control
    depth: deep
    status: success
    summary: GitHub App vs Agent SDK vs self-hosted bot — survey of mobile-friendly approval flows.
    citations: 32
    reading_time_min: 12
  - slug: branch-and-pr-automation
    title: Branch and PR automation
    depth: standard
    status: success
    summary: How a "go" message produces a branch and PR without a local checkout.
    citations: 18
    reading_time_min: 7
  - slug: synology-preview-deployments
    title: Synology preview deployments
    depth: standard
    status: success
    summary: Container Manager / Docker Compose lifecycle per branch.
    citations: 21
    reading_time_min: 9
---

The five angles split cleanly along a routing-vs-orchestration axis, with one cross-cutting concern (auth) appearing in three of them. The Slack remote-control angle is the gating decision: every other choice depends on whether triggers come through a GitHub App or a self-hosted bot.

(Body continues — synthesised prose with citations.)
EOF
```

- [ ] **Step 18.2: Create the mixed-success preview.**

```bash
mkdir -p _previews/expedition-partial
cat > _previews/expedition-partial/index.html <<'EOF'
---
layout: expedition
title: Development work on the go (partial)
date: 2026-04-26
topic: Design and implement an end-to-end workflow that lets the user chat with Claude Code on Slack…
format: auto
synthesis: true
citations: 50
reading_time_min: 22
children:
  - slug: slack-claude-code-remote-control
    title: Slack ↔ Claude Code remote control
    depth: deep
    status: success
    summary: GitHub App vs Agent SDK survey.
    citations: 32
    reading_time_min: 12
  - slug: per-feature-subdomain-routing
    title: Per-feature subdomain routing
    depth: deep
    status: failed
    summary: hard timeout
  - slug: orchestration-and-state
    title: Orchestration and state
    depth: ceo
    status: success
    summary: Glue across the four pieces.
    citations: 18
    reading_time_min: 10
---

Two angles produced output; the routing angle did not complete in this run (reason: hard timeout). The Slack and orchestration angles already converge on a single recommendation — see the per-angle pages.
EOF
```

- [ ] **Step 18.3: Verify previews render.**

Build the site (existing `serve.ps1` or `bundle exec jekyll build` if available) and load `/previews/expedition/` and `/previews/expedition-partial/`. Visual review:

- Hero shows expedition badge, "3 angles · 3 succeeded" / "3 angles · 2 succeeded · 1 placeholders".
- Synthesis section renders content above the children grid.
- Children grid: success cards are clickable, failed card is greyed with a "failed" pill and "Reason: …" body, no link.
- Atlas home shows the parent with the expedition badge and the "3 angles" overlay.

If any of those break, fix the layout/include/css, repeat.

- [ ] **Step 18.4: Commit.**

```bash
git add _previews/expedition _previews/expedition-partial
git commit -m "test(atlas): expedition full + partial preview fixtures"
```

### Stage 3 commit checkpoint

- [ ] **Step S3.C: Final verification across both repos.**

In `scout`:

```bash
SCOUT_SKIP_CLAUDE=1 \
  bash -c 'for t in tests/test_*.sh; do echo "==> $t"; bash "$t" || exit 1; done'
```

In `atlas`: visual review of both previews and the home grid in your local Jekyll build.

If both pass, Stage 3 is complete and the feature is fully shipped.

---

## Self-Review

This section is the executor's checklist for verifying spec coverage before declaring the plan complete. The plan author has already run it once; re-running it as the executor is recommended.

### Spec coverage map

| Spec section | Plan coverage |
|---|---|
| Goal: decompose wide topics | Stages 1–3 collectively |
| Sharpener T2 judgment | Task 2 (sharpen.md instructions) |
| Bot comment template (split, Sub-topics section, Go header) | Stage 1 (shipped 2026-04-26 — pulled forward from original Task 4) |
| Bot comment escape-hatch checkbox + final disclaimer | Stage 2 Task 4 (slimmed) |
| Sub-topic continuity across user re-sharpen | Stage 2 Task 4b (`PREVIOUS_SUB_TOPICS` harvest + sharpen.md Rule 7 extension) |
| Sub-topic line regex + lenience | Task 3 (parse_sub_topics + tests) |
| Fuzzy depth matching ≤ 2 | Task 3 (_lev + _snap_depth + tests) |
| Internal-code aliases (ceo/standard/deep) | Task 3 (_snap_depth) |
| Mutual exclusion (both Start ticked → as_one wins) | Task 3 (parse_start_choice + tests) |
| `run-decompose.sh` orchestration | Tasks 6, 7, 8, 9 |
| Sequential children, single self-hosted runner | Task 6 (loop is sequential by construction) |
| Resumability (skip non-placeholder) | Task 6 (_child_is_success) |
| Soft 4h / Hard 4h20m timeouts | Task 6 + Task 7 tests |
| ≥2 success synthesis gate | Task 8 + tests |
| Synthesis skill instructions | Task 5 (synthesis.md) |
| Failure placeholder frontmatter | Task 6 (_write_placeholder) + Task 9 tests |
| Manifest.json | Task 6 (manifest_path block) |
| F2 partial publish, issue stays open | Task 12 (publish.sh failed-children scan) |
| Soft-fail comment lists failed children | Task 12 |
| Workflow trigger (both Start variants) | Task 11 |
| Routing in research-from-issue.sh | Task 10 |
| Atlas L2 expedition layout | Task 13 |
| Children grid (success/failed states) | Task 14 |
| Expedition badge + palette token | Tasks 15, 16 |
| "N angles" home overlay | Task 17 |
| Preview fixtures | Task 18 |

No spec sections without coverage.

### Placeholder scan

- No "TBD", "TODO", or "implement later" instructions — every step has runnable code or commands.
- Two soft references to existing files require the executor to *read* the file before editing (Task 12.1 to find soft-fail line numbers; Task 17.1 to find depth-badge style locations). Both are unavoidable: the existing files weren't read by the plan author at writing time. Each soft reference includes the exact `grep` command the executor should run to locate the insertion point.

### Type / signature consistency

- `SUB_TOPICS` array entries use `title|depth|rationale|checked` shape consistently across `parse_sub_topics`, the resumability test, the timeout test, the synthesis-gate test, and `run-decompose.sh`'s loop (`IFS='|' read -r ctitle cdepth crationale cchecked`).
- Internal depth codes (`ceo`/`standard`/`deep`) are used everywhere in `run-decompose.sh` and the parser; display names (`recon`/`survey`/`expedition`) only appear in user-facing strings (bot comment, frontmatter, layout). The `_snap_depth` function is the single point of conversion.
- `PARENT_DIR`, `SCOUT_DIR`, `RESEARCH_DIR` are referenced consistently with the same meaning across all scripts.
- `_frontmatter_field` is defined once in `run-decompose.sh` and re-used; `_child_is_success` calls it to read `status`.

If you spot any drift while executing, treat it as a bug in the plan and stop to flag it before continuing.
