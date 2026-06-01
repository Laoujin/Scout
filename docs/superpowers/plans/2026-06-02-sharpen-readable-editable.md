# Readable, Editable Sharpened Proposals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the sharpened-proposal comment a single, readable, in-place-editable markdown brief (bold lead line + bullets) that is also exactly what gets researched — removing the duplicate blockquote and the awkward one-line code fence.

**Architecture:** The sharpener emits a structured brief instead of one paragraph. `issue-comment.sh` renders it as plain markdown between the existing `<!-- scout-topic-start/end -->` HTML markers (no blockquote, no fence). A shared `extract_topic()` reads the brief back, with a compat shim that unwraps the old `scout-topic` fence so existing issues keep working with no migration.

**Tech Stack:** Bash, awk/sed, GitHub Actions, gh CLI. Tests are standalone bash scripts under `tests/` with a pass/fail harness (no external runner).

---

## File Structure

- `scripts/lib-issue-parse.sh` — add `extract_topic()` (compat shim) and `topic_title()` (first-line slug source). Both are pure string functions, unit-testable.
- `scripts/issue-comment.sh` — render brief between markers; delete blockquote + fence.
- `scripts/research-from-issue.sh` — read topic via `extract_topic`; slug decompose parent from `topic_title`.
- `.github/workflows/research.yml` — re-sharpen reads `PREVIOUS_SHARPENED` via `extract_topic`.
- `skills/scout/sharpen.md` — new structured output format + examples.
- `tests/test_lib_topic_extract.sh` — NEW: `extract_topic` (3 formats) + `topic_title`.
- `tests/test_issue_comment_series_render.sh` — switch fence-extraction asserts to marker-extraction; assert no blockquote/fence.
- `tests/test_sharpen_snapshots.sh` — narrow invariant becomes "bold lead + bullets, no fences".
- `tests/fixtures/sharpen/narrow_topic.expected.md`, `wide_topic.expected.md` — re-author to new format (hand-written; live re-capture via `UPDATE_SNAPSHOTS=1` needs Claude and is left for the operator).

**Test invocation:** a single test file runs with `bash tests/<file>.sh` (exit 0 = pass). Full suite: `for t in tests/test_*.sh; do echo "== $t"; SCOUT_SKIP_CLAUDE=1 bash "$t" || break; done`.

---

## Task 1: `extract_topic()` + `topic_title()` in lib-issue-parse.sh

**Files:**
- Create: `tests/test_lib_topic_extract.sh`
- Modify: `scripts/lib-issue-parse.sh` (add two functions after `_trim_blanks`, before `_normalize_depth`)

- [ ] **Step 1: Write the failing test**

Create `tests/test_lib_topic_extract.sh`:

```bash
#!/usr/bin/env bash
# Tests for extract_topic() and topic_title() in lib-issue-parse.sh.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-issue-parse.sh"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1 (want [$2] got [$3])"; }

# --- new format: markdown between markers ---
NEW=$'### Sharpened proposal\n\n<!-- scout-topic-start -->\n**Decision framework: ripgrep vs ag.**\n\n- Scope: 50k-file repo.\n- Output: comparison table.\n<!-- scout-topic-end -->\n\n- [ ] **Start research**'
got="$(extract_topic "$NEW")"
assert_eq "new: keeps bold lead"  "**Decision framework: ripgrep vs ag.**" "$(printf '%s\n' "$got" | sed -n '1p')"
assert_eq "new: keeps bullet"     "- Output: comparison table."             "$(printf '%s\n' "$got" | sed -n '4p')"
printf '%s' "$got" | grep -q 'scout-topic' && fail "new: marker/fence leaked" || pass "new: no marker/fence leak"

# --- recent format: scout-topic fence INSIDE markers (compat) ---
OLD=$'<!-- scout-topic-start -->\n```scout-topic\nDecision framework comparing ripgrep and ag. Decision-only.\n```\n<!-- scout-topic-end -->'
got="$(extract_topic "$OLD")"
assert_eq "fence-in-markers: unwrapped" "Decision framework comparing ripgrep and ag. Decision-only." "$got"

# --- very old format: bare fence, no markers (fallback) ---
BARE=$'### Sharpened proposal\n\n```scout-topic\nA bare-fenced topic.\n```\n\n- [ ] **Start research**'
got="$(extract_topic "$BARE")"
assert_eq "bare-fence fallback: extracted" "A bare-fenced topic." "$got"

# --- topic_title: strips bold + bullet, first non-empty line ---
assert_eq "title: strips bold"   "Decision framework: ripgrep vs ag." "$(topic_title $'**Decision framework: ripgrep vs ag.**\n\n- Scope: x')"
assert_eq "title: strips bullet" "Lead line"                          "$(topic_title $'- Lead line\n- second')"
assert_eq "title: plain"         "Just prose."                        "$(topic_title 'Just prose.')"

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lib_topic_extract.sh`
Expected: FAIL — `extract_topic: command not found` (function not defined yet).

- [ ] **Step 3: Add the functions**

In `scripts/lib-issue-parse.sh`, insert after the `_trim_blanks()` function (line ~41) and before `_normalize_depth()`:

```bash
# Extract the sharpened topic from a bot comment body. Prefers the HTML-marker
# region (current format); falls back to a bare ```scout-topic fence for
# pre-marker comments. Unwraps an old ```scout-topic fence found *inside* the
# markers so already-sharpened issues keep working.
# COMPAT: the fence-unwrap branch + bare-fence fallback can be removed once all
# pre-2026-06 sharpened issues are closed.
extract_topic() {
  local body="$1" region
  region="$(printf '%s' "$body" | awk '
    /<!-- scout-topic-start -->/ { in_m=1; next }
    /<!-- scout-topic-end -->/   { in_m=0; exit }
    in_m { print }
  ')"
  if [ -z "$region" ]; then
    region="$(printf '%s' "$body" | awk '
      /^```scout-topic[[:space:]]*$/ { in_b=1; next }
      /^```[[:space:]]*$/ && in_b { exit }
      in_b { print }
    ')"
  fi
  case "$region" in
    '```scout-topic'*)
      region="$(printf '%s' "$region" | awk '
        /^```scout-topic/ { f=1; next }
        /^```/            { f=0 }
        f')" ;;
  esac
  printf '%s' "$region" | _trim_blanks
}

# First non-empty line of a (possibly structured) topic, stripped of bold
# markers and a leading bullet — used as the slug/title source.
topic_title() {
  printf '%s\n' "$1" | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/\*\*//g;s/^[-*][[:space:]]*//;s/[[:space:]]*$//;p;q}'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lib_topic_extract.sh`
Expected: PASS — `Results: 9 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_lib_topic_extract.sh scripts/lib-issue-parse.sh
git commit -m "Add extract_topic + topic_title with old-format compat shim"
```

---

## Task 2: issue-comment.sh renders markdown between markers

**Files:**
- Modify: `tests/test_issue_comment_series_render.sh` (asserts)
- Modify: `scripts/issue-comment.sh` (drop blockquote + fence)

- [ ] **Step 1: Update the test to the new format**

In `tests/test_issue_comment_series_render.sh`, replace each fence-extraction asserter. The current marker is the ` ```scout-topic ` fence; the new marker is the HTML comment pair. Change all three `awk '/```scout-topic/{f=1;next} /```/{f=0} f'` invocations to:

```bash
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f'
```

So line 36, line 64, line 67 become (respectively, keeping their grep targets):

```bash
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-series' \
  && fail "narrow: scout-series leaked into topic block" \
  || pass "narrow: scout-series stripped from topic block"
```
```bash
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-subtopics' \
  && fail "wide: scout-subtopics leaked into topic block" \
  || pass "wide: scout-subtopics stripped from topic block"
```
```bash
awk '/<!-- scout-topic-start -->/{f=1;next} /<!-- scout-topic-end -->/{f=0} f' "$CAPTURE_FILE" | grep -q 'scout-series' \
  && fail "wide: scout-series leaked into topic block" \
  || pass "wide: scout-series stripped from topic block"
```

Then add, immediately after the narrow `run_comment "$TOPIC"` block (after line 38), two new assertions:

```bash
grep -qE '^> ' "$CAPTURE_FILE" && fail "narrow: blockquote should be gone" || pass "narrow: no blockquote"
grep -qF '```scout-topic' "$CAPTURE_FILE" && fail "narrow: scout-topic fence should be gone" || pass "narrow: no scout-topic fence"
grep -qF '<!-- scout-topic-start -->' "$CAPTURE_FILE" && pass "narrow: marker present" || fail "narrow: marker missing"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_issue_comment_series_render.sh`
Expected: FAIL — "scout-topic fence should be gone" (issue-comment.sh still emits the fence) and the marker-extraction asserts mis-count.

- [ ] **Step 3: Update issue-comment.sh**

In `scripts/issue-comment.sh`:

Delete the blockquote line (line 56-57):

```bash
# Blockquote each line of the topic for the human-readable section.
quoted="$(printf '%s\n' "$TOPIC_ONLY" | sed 's/^/> /')"
```

In the **sub-topics branch** (the `if [ -n "$SUB_TOPICS_BLOCK" ]` heredoc), replace:

```
${quoted}

<!-- scout-topic-start -->
\`\`\`scout-topic
${TOPIC_ONLY}
\`\`\`
<!-- scout-topic-end -->
```
with:
```
<!-- scout-topic-start -->
${TOPIC_ONLY}
<!-- scout-topic-end -->
```

In the **narrow branch** (the `else` heredoc), make the identical replacement.

Update the header comment (line 3) from:
```
# Comment shape: human-readable blockquote + machine-parseable scout-topic fenced
# block + a [ ] Start research checkbox the user ticks to publish to Atlas.
```
to:
```
# Comment shape: the sharpened brief as markdown between scout-topic HTML
# markers (single source — readable + machine-parseable) + a [ ] Start research
# checkbox the user ticks to publish to Atlas.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_issue_comment_series_render.sh`
Expected: PASS — all asserts green including "no blockquote", "no scout-topic fence", "marker present".

- [ ] **Step 5: Commit**

```bash
git add tests/test_issue_comment_series_render.sh scripts/issue-comment.sh
git commit -m "Render sharpened brief as markdown between markers, drop blockquote+fence"
```

---

## Task 3: research-from-issue.sh reads via extract_topic, slugs the title

**Files:**
- Modify: `scripts/research-from-issue.sh`

(No new unit test: `extract_topic`/`topic_title` are covered by Task 1, and this script `exec`s the pipeline so it isn't unit-tested in the suite. Verified by `bash -n` + the suite's decompose tests staying green.)

- [ ] **Step 1: Replace the inline extractor**

In `scripts/research-from-issue.sh`, replace lines 18-28:

```bash
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
```
with:
```bash
# Topic — sharpened brief from the bot comment (markers, with old-fence compat).
TOPIC="$(extract_topic "$BOT_COMMENT_BODY")"

if [ -z "$TOPIC" ]; then
  echo "Error: could not extract sharpened topic from bot comment." >&2
  exit 1
fi
```

- [ ] **Step 2: Slug the decompose parent from the title line**

In the same file, replace line 49:

```bash
  PARENT_SLUG="$(slugify "$TOPIC")"
```
with:
```bash
  PARENT_SLUG="$(slugify "$(topic_title "$TOPIC")")"
```

And the uniquifier loop just below it (line 52) likewise:

```bash
    PARENT_SLUG="$(slugify "$(topic_title "$TOPIC")")-${n}"
```

- [ ] **Step 3: Syntax-check**

Run: `bash -n scripts/research-from-issue.sh && echo OK`
Expected: `OK`.

- [ ] **Step 4: Confirm decompose suite still passes**

Run: `SCOUT_SKIP_CLAUDE=1 bash tests/test_run_decompose_publish.sh`
Expected: PASS (or unchanged from baseline — see Task 6 baseline note).

- [ ] **Step 5: Commit**

```bash
git add scripts/research-from-issue.sh
git commit -m "Read topic via extract_topic; slug decompose parent from title line"
```

---

## Task 4: research.yml re-sharpen uses extract_topic

**Files:**
- Modify: `.github/workflows/research.yml` (the `resharpen-on-comment` step)

(Workflow inline bash; `extract_topic` itself is covered by Task 1. Verified by re-extracting the surrounding YAML stays valid.)

- [ ] **Step 1: Replace the inline PREVIOUS_SHARPENED extractor**

In `.github/workflows/research.yml`, inside the `resharpen-on-comment` step, the block sources `scripts/lib-issue-parse.sh` already. Replace the inline awk that sets `PREVIOUS_SHARPENED` (the `awk '/^```scout-topic ... in_block { print }'` over `$PREVIOUS_BODY`):

```bash
          PREVIOUS_SHARPENED="$(printf '%s' "$PREVIOUS_BODY" | awk '
            /^```scout-topic[[:space:]]*$/ { in_block=1; next }
            /^```[[:space:]]*$/ && in_block { exit }
            in_block { print }
          ')"
```
with:
```bash
          PREVIOUS_SHARPENED="$(extract_topic "$PREVIOUS_BODY")"
```

Leave the `PREVIOUS_SUB_TOPICS` and `PREVIOUS_SERIES` awk blocks unchanged.

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/research.yml')); print('YAML OK')"`
Expected: `YAML OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/research.yml
git commit -m "Re-sharpen reads previous topic via extract_topic"
```

---

## Task 5: sharpen.md structured output + snapshot test + fixtures

**Files:**
- Modify: `skills/scout/sharpen.md`
- Modify: `tests/test_sharpen_snapshots.sh` (narrow invariant)
- Modify: `tests/fixtures/sharpen/narrow_topic.expected.md`, `wide_topic.expected.md`

- [ ] **Step 1: Update the snapshot test's narrow invariant**

In `tests/test_sharpen_snapshots.sh`, replace the narrow block:

```bash
# --- Narrow: no fenced blocks, no bullet lines (single paragraph only) ---
if [ -s "$NARROW" ]; then
  fences=$(grep -c '^```' "$NARROW" || true)
  bullets=$(grep -cE '^[-*] ' "$NARROW" || true)
  [ "$fences" -eq 0 ] && pass "narrow: no fenced blocks" \
                      || fail "narrow: $fences fenced-block line(s) found, expected 0"
  [ "$bullets" -eq 0 ] && pass "narrow: no bullet lines" \
                       || fail "narrow: $bullets bullet line(s) found, expected 0"
fi
```
with:
```bash
# --- Narrow: structured brief — bold lead line + >=1 bullet, no fenced blocks ---
if [ -s "$NARROW" ]; then
  fences=$(grep -c '^```' "$NARROW" || true)
  bullets=$(grep -cE '^[-*] ' "$NARROW" || true)
  lead=$(grep -cE '^\*\*.+\*\*' "$NARROW" || true)
  [ "$fences" -eq 0 ] && pass "narrow: no fenced blocks" \
                      || fail "narrow: $fences fenced-block line(s) found, expected 0"
  [ "$bullets" -ge 1 ] && pass "narrow: has bullet lines ($bullets)" \
                       || fail "narrow: no bullet lines, expected >=1"
  [ "$lead" -ge 1 ] && pass "narrow: has bold lead line" \
                    || fail "narrow: no bold lead line found"
fi
```

The wide block is unchanged: it asserts exactly two fences (the `scout-subtopics` open/close) and the canonical sub-topic regex, none of which the new brief bullets match.

- [ ] **Step 2: Re-author the narrow fixture**

Overwrite `tests/fixtures/sharpen/narrow_topic.expected.md` with:

```
**Decision framework: ripgrep vs ag vs ack vs grep for repository-scale code search (2026).**

- Scope: searching a 50k-file repository; decision-only.
- Compare: raw speed on a large tree, ergonomic fit (PCRE/regex flavor, smart-case, gitignore awareness), packaging maturity, maintenance state.
- Output: a comparison table of the four tools with a clear recommendation.
```

- [ ] **Step 3: Re-author the wide fixture**

Overwrite `tests/fixtures/sharpen/wide_topic.expected.md` with (brief now structured; `scout-subtopics` block preserved):

```
**Design and implement a Slack-driven, per-feature deploy workflow for Claude Code on Synology (2026).**

- Scope: chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology.
- Cover: the wiring, state, and failure modes that tie the pieces together.
- Constraints: favor production-ready open-source components.
```scout-subtopics
- [x] (expedition) **Slack ↔ Claude Code remote control** — Per-project channels, message → agent invocation, approval/handoff, mobile UX.
- [x] (survey) **Branch and PR automation from a remote trigger** — How a "go" message produces a branch + commits + PR without a local checkout.
- [x] (survey) **Synology preview deployments** — Container Manager / Docker Compose lifecycle per branch, build pipeline, teardown on branch delete.
- [x] (expedition) **Per-feature subdomain routing** — Wildcard reverse proxy, wildcard TLS via DNS-01, dynamic config from branch metadata.
- [x] (recon) **Orchestration and state** — Glue tying the pieces; where state lives; failure modes and recovery.
```
```

> NOTE: these fixtures are hand-authored representatives of the new format. To regenerate from live Claude after the prompt change, the operator runs `UPDATE_SNAPSHOTS=1 bash tests/test_sharpen_snapshots.sh` (needs Claude auth) and reviews the diff.

- [ ] **Step 4: Rewrite the sharpen.md Output section**

In `skills/scout/sharpen.md`, replace the first paragraph of `## Output` (line 80):

```
Always emit the sharpened topic as one paragraph. No preamble ("Here is..."), no quotes, no bullet list, no markdown headers, no explanation of what you changed. Just the paragraph, ready to be passed verbatim to the research playbook.
```
with:

```
Emit the sharpened topic as a structured brief: a **bold one-line deliverable** (verb-led — "Decision framework…", "Survey of…", "Compare…"), then 2–5 markdown bullets. Use bullets such as `Scope:`, `Compare:` (the axes from rule 3), `Constraints:` (steering hints, verbatim), and `Output:` (the shape implied by depth). No preamble ("Here is…"), no quotes, no `#` headings (the bold lead line is the title), no explanation of what you changed. Keep it tight — don't pad. The whole brief is passed verbatim to the research playbook, so the bold lead line should read as the deliverable on its own.
```

- [ ] **Step 5: Update the two examples in sharpen.md**

Replace the **narrow** example Output block (currently the single "Decision framework comparing ripgrep…" paragraph) with:

```
**Decision framework: ripgrep vs ag vs ack vs grep for repository-scale code search (2026).**

- Scope: searching a 50k-file repository; decision-only.
- Compare: raw speed on a large tree, ergonomic fit (PCRE/regex flavor, smart-case, gitignore awareness), packaging maturity, maintenance state.
- Output: a comparison table of the four tools with a clear recommendation.
```

Replace the **wide** example Output paragraph (currently "Design and implement an end-to-end workflow…") with the structured brief — keeping the existing `scout-subtopics` block beneath it unchanged:

```
**Design and implement a Slack-driven, per-feature deploy workflow for Claude Code on Synology (2026).**

- Scope: chat with Claude Code on Slack to spec, build, and review a feature, then auto-deploy each branch to a per-feature subdomain on Synology.
- Cover: the wiring, state, and failure modes that tie the pieces together.
- Constraints: favor production-ready open-source components.
```

- [ ] **Step 6: Run the snapshot test (structural, no Claude)**

Run: `bash tests/test_sharpen_snapshots.sh`
Expected: PASS — narrow now asserts bold lead + bullets; wide unchanged.

- [ ] **Step 7: Commit**

```bash
git add skills/scout/sharpen.md tests/test_sharpen_snapshots.sh tests/fixtures/sharpen/narrow_topic.expected.md tests/fixtures/sharpen/wide_topic.expected.md
git commit -m "Sharpen into a structured brief (bold lead + bullets)"
```

---

## Task 6: Full-suite regression + spec/plan housekeeping

**Files:** none (verification only), then optionally the spec doc note.

- [ ] **Step 1: Baseline note**

Before claiming regressions, know that some suite tests invoke `claude` or need tools not present in every env. Run each with `SCOUT_SKIP_CLAUDE=1`. Treat a test as a regression ONLY if it passed before these changes and fails after. The directly-touched tests that MUST pass: `test_lib_topic_extract.sh`, `test_issue_comment_series_render.sh`, `test_sharpen_snapshots.sh`, `test_lib_issue_parse_subtopics.sh`.

- [ ] **Step 2: Run the suite**

Run:
```bash
for t in tests/test_*.sh; do
  echo "== $t"
  SCOUT_SKIP_CLAUDE=1 bash "$t" >/tmp/out 2>&1 && echo "  ok" || { echo "  FAIL"; tail -20 /tmp/out; }
done
```
Expected: the four MUST-pass tests print `ok`. Investigate any newly-failing test; pre-existing env failures (missing `claude`, etc.) are not regressions.

- [ ] **Step 3: Final commit (if any housekeeping edits were needed)**

```bash
git add -A
git commit -m "Tidy: sharpen readable-brief follow-ups"
```
(Skip if nothing changed.)

---

## Self-Review

- **Spec coverage:** structured brief (T5) ✓; markdown between markers, drop blockquote+fence (T2) ✓; `extract_topic` shim (T1) ✓ used by reader (T3) and re-sharpen (T4) ✓; title-line slug (T3) ✓; tests for all three extract formats + render + slug (T1/T2/T5) ✓; backward compat / no migration (T1 shim) ✓.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Naming consistency:** `extract_topic` and `topic_title` used identically across T1/T3/T4. Markers `<!-- scout-topic-start -->` / `<!-- scout-topic-end -->` consistent across render (T2) and extract (T1).
- **Known limitation:** snapshot fixtures are hand-authored, not Claude-captured; operator can refresh with `UPDATE_SNAPSHOTS=1`. Documented in T5 Step 3.
