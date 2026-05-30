# Series Suggestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During the sharpen step, suggest adding a new research entry to an existing Atlas series via a ticked-by-default checkbox; when "Start research" fires with it still ticked, the publish step adds the entry to `_data/series.yml`.

**Architecture:** Rides the existing `scout-subtopics` pattern. The sharpener (fed the current Atlas series manifest, fetched best-effort) emits a `scout-series` block carrying *intent* (series slug + optional group). `issue-comment.sh` renders it as a `### Series` checkbox. At research time `parse_series` reads the ticked block; after `run.sh` finalizes the slug, `add-to-series.sh` does a comment-preserving, idempotent, fail-soft text insert into the Atlas checkout's `series.yml`, swept into the publish commit. v1 covers the single-pass path only.

**Tech Stack:** Bash, awk, GitHub Actions, `gh`/`curl`. Tests are standalone bash scripts run via `bash tests/test_*.sh` (PASS/FAIL counter harness, exit 1 on any fail).

**Spec:** `docs/superpowers/specs/2026-05-30-series-suggestion-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `scripts/lib-issue-parse.sh`            | Issue/comment parsing helpers | Add `parse_series` |
| `scripts/add-to-series.sh`              | Idempotent, fail-soft YAML insert | Create |
| `scripts/issue-comment.sh`              | Render sharpened proposal comment | Add `### Series` rendering |
| `skills/scout/sharpen.md`               | Sharpen skill prompt | Add series-match rule + `scout-series` output |
| `scripts/sharpen.sh`                    | Sharpen runner | Inject `SERIES_MANIFEST` / `PREVIOUS_SERIES` |
| `scripts/research-from-issue.sh`        | Issue→pipeline glue | Call `parse_series`, export vars |
| `scripts/run.sh`                        | Single-pass research run | Call `add-to-series.sh` before publish |
| `.github/workflows/research.yml`        | Orchestration | Fetch manifest + pass to sharpen; extract `PREVIOUS_SERIES` on resharpen |
| `tests/test_lib_issue_parse_series.sh`  | `parse_series` unit tests | Create |
| `tests/test_add_to_series.sh`           | insert/idempotent/soft-fail tests | Create |
| `tests/test_issue_comment_series_render.sh` | comment-render tests | Create |
| `tests/test_sharpen_series_injection.sh`| sharpen input injection tests | Create |

---

## Task 1: `parse_series` in lib-issue-parse.sh

**Files:**
- Test: `tests/test_lib_issue_parse_series.sh` (create)
- Modify: `scripts/lib-issue-parse.sh` (append new function)

- [ ] **Step 1: Write the failing test**

Create `tests/test_lib_issue_parse_series.sh`:

```bash
#!/usr/bin/env bash
# Tests for parse_series() in lib-issue-parse.sh.

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

echo "Testing parse_series()..."

# --- ticked, with group ---
C=$'### Series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich weekend.\n\n### Go\n- [ ] **Start research**\n'
parse_series "$C"
assert_eq "grouped: slug"  "michelin-weekends" "$SERIES_SLUG"
assert_eq "grouped: group" "Germany"           "$SERIES_GROUP"

# --- ticked, flat (no group) ---
C=$'### Series\n- [x] **sessions-and-workshops** \xe2\x80\x94 talk prep.\n'
parse_series "$C"
assert_eq "flat: slug"  "sessions-and-workshops" "$SERIES_SLUG"
assert_eq "flat: group" ""                        "$SERIES_GROUP"

# --- unticked -> nothing ---
C=$'### Series\n- [ ] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich.\n'
parse_series "$C"
assert_eq "unticked: slug"  "" "$SERIES_SLUG"
assert_eq "unticked: group" "" "$SERIES_GROUP"

# --- absent section -> nothing ---
C=$'### Go\n- [ ] **Start research**\n'
parse_series "$C"
assert_eq "absent: slug"  "" "$SERIES_SLUG"
assert_eq "absent: group" "" "$SERIES_GROUP"

# --- lenient: ascii separators, asterisk bullet, leading ws, slash group ---
C=$'### Series\n  * [X] **michelin-weekends** / Germany - Munich.\n'
parse_series "$C"
assert_eq "lenient: slug"  "michelin-weekends" "$SERIES_SLUG"
assert_eq "lenient: group" "Germany"           "$SERIES_GROUP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lib_issue_parse_series.sh`
Expected: FAIL — `parse_series: command not found` / non-zero exit.

- [ ] **Step 3: Implement `parse_series`**

Append to `scripts/lib-issue-parse.sh` (after `parse_start_choice`):

```bash
# --- Series parsing -------------------------------------------------------
#
# parse_series reads the `### Series` section of a bot comment and exports:
#   SERIES_SLUG  — series slug if a ticked line is present, else ""
#   SERIES_GROUP — group label if present on that line, else ""
# Only a ticked ([x]/[X]) line counts. Line shape (lenient):
#   - [x] **<slug>** [(› | /) <group>] [(— | -) <rationale>]
parse_series() {
  local body="$1"
  SERIES_SLUG=""; SERIES_GROUP=""
  local section line
  section="$(_extract_section "$body" 'Series')"
  [ -n "$section" ] || { export SERIES_SLUG SERIES_GROUP; return 0; }
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"   # strip leading whitespace
    # bullet, ticked box, **slug**, optional (›|/) group, optional (—|-) rationale
    if [[ "$line" =~ ^[-*][[:space:]]+\[[xX]\][[:space:]]*\*\*([^*]+)\*\*([[:space:]]*(›|/)[[:space:]]*([^—-]+?))?([[:space:]]*(—|-)[[:space:]]*.*)?$ ]]; then
      SERIES_SLUG="${BASH_REMATCH[1]}"
      SERIES_GROUP="${BASH_REMATCH[4]:-}"
      # trim trailing whitespace from captures
      SERIES_SLUG="${SERIES_SLUG%"${SERIES_SLUG##*[![:space:]]}"}"
      SERIES_GROUP="${SERIES_GROUP%"${SERIES_GROUP##*[![:space:]]}"}"
      break
    fi
  done <<< "$section"
  export SERIES_SLUG SERIES_GROUP
}
```

Note for implementer: bash ERE has no lazy `+?`; if the regex misbehaves on the group capture, split on the separator in two steps instead — match `**slug**` and the remainder, then if remainder starts with `›`/`/`, take the text up to the first `—`/`-` as the group. Tests pin the required behavior; iterate until green.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lib_issue_parse_series.sh`
Expected: `Results: 10 passed, 0 failed`

- [ ] **Step 5: Confirm no regression in sibling parser**

Run: `bash tests/test_lib_issue_parse_subtopics.sh`
Expected: existing PASS count unchanged, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib-issue-parse.sh tests/test_lib_issue_parse_series.sh
git commit -m "feat: parse_series reads ### Series checkbox from bot comment"
```

---

## Task 2: `add-to-series.sh` — idempotent YAML insert

**Files:**
- Test: `tests/test_add_to_series.sh` (create)
- Create: `scripts/add-to-series.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_add_to_series.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/add-to-series.sh — comment-preserving, idempotent, fail-soft.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/add-to-series.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

make_yaml() {
  cat > "$1" <<'YAML'
# series manifest — keep this header comment.
- slug: michelin-weekends
  title: Michelin weekend getaways
  blurb: Weekends built around a starred restaurant.
  groups:
    - label: Belgium
      entries:
        - 2026-05-23-la-table-de-maxime
    - label: Germany
      entries:
        - 2026-05-27-sonnora

- slug: sessions-and-workshops
  title: Sessions & workshops
  blurb: Talks and workshops.
  entries:
    - 2026-05-23-vibe-coding
YAML
}

# --- insert under an existing group ---
Y="$WORK/a.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
grep -qE '^        - 2026-05-29-munich$' "$Y" \
  && pass "grouped: entry inserted at 8-space indent" \
  || fail "grouped: entry not inserted correctly"
# inserted into Germany group, not Belgium: line must come after the Germany label
gline=$(grep -n 'label: Germany' "$Y" | cut -d: -f1)
eline=$(grep -n '2026-05-29-munich' "$Y" | cut -d: -f1)
[ "$eline" -gt "$gline" ] && pass "grouped: placed under Germany" || fail "grouped: wrong group"
grep -q '# series manifest — keep this header comment.' "$Y" \
  && pass "grouped: header comment preserved" || fail "grouped: header comment lost"

# --- insert into a flat series ---
Y="$WORK/b.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-mcp-session" sessions-and-workshops
grep -qE '^    - 2026-05-29-mcp-session$' "$Y" \
  && pass "flat: entry inserted at 4-space indent" \
  || fail "flat: entry not inserted correctly"

# --- idempotent: re-run is a no-op (no duplicate) ---
Y="$WORK/c.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
cnt=$(grep -c '2026-05-29-munich' "$Y")
[ "$cnt" -eq 1 ] && pass "idempotent: single occurrence" || fail "idempotent: $cnt occurrences"

# --- missing series: soft-skip, file unchanged, exit 0 ---
Y="$WORK/d.yml"; make_yaml "$Y"; before=$(md5sum "$Y" | cut -d' ' -f1)
SOFT="$WORK/soft.log"
SOFT_FAIL_LOG="$SOFT" bash "$SCRIPT" "$Y" "2026-05-29-x" no-such-series; rc=$?
after=$(md5sum "$Y" | cut -d' ' -f1)
[ "$rc" -eq 0 ] && pass "missing series: exit 0" || fail "missing series: exit $rc"
[ "$before" = "$after" ] && pass "missing series: file unchanged" || fail "missing series: file mutated"
grep -q 'series:' "$SOFT" && pass "missing series: logged to SOFT_FAIL_LOG" || fail "missing series: not logged"

# --- missing group: soft-skip ---
Y="$WORK/e.yml"; make_yaml "$Y"; before=$(md5sum "$Y" | cut -d' ' -f1)
bash "$SCRIPT" "$Y" "2026-05-29-x" michelin-weekends Nowhere; rc=$?
after=$(md5sum "$Y" | cut -d' ' -f1)
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && pass "missing group: exit 0, unchanged" || fail "missing group: rc=$rc changed?"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_add_to_series.sh`
Expected: FAIL — script missing (`No such file`), non-zero exit.

- [ ] **Step 3: Implement `scripts/add-to-series.sh`**

Create `scripts/add-to-series.sh`:

```bash
#!/usr/bin/env bash
# add-to-series.sh — idempotently add a research entry to an EXISTING series in
# Atlas's _data/series.yml. Comment-preserving text insert. Never creates a new
# series or group. Fail-soft: any miss logs and exits 0 (never blocks publish).
#
# Usage: add-to-series.sh <series.yml> <entry-slug> <series-slug> [group-label]

set -uo pipefail

YAML="${1:?series.yml path required}"
ENTRY="${2:?entry slug required}"
SERIES="${3:?series slug required}"
GROUP="${4:-}"

soft_fail() {
  echo "add-to-series: $1 — skipping" >&2
  [ -n "${SOFT_FAIL_LOG:-}" ] && echo "series: $1" >> "$SOFT_FAIL_LOG"
  exit 0
}

[ -f "$YAML" ] || soft_fail "series.yml not found at $YAML"

# Idempotent: entry already a member anywhere in the file.
if grep -qE "^[[:space:]]*-[[:space:]]+${ENTRY}[[:space:]]*$" "$YAML"; then
  echo "add-to-series: $ENTRY already present — no-op" >&2
  exit 0
fi

tmp="$(mktemp)"
awk -v series="$SERIES" -v group="$GROUP" -v entry="$ENTRY" '
  function indent(s){ match(s, /^ */); return RLENGTH }
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { lines[NR] = $0 }
  END {
    n = NR
    # 1. locate series block [s_start, s_end)
    s_start = 0
    for (i = 1; i <= n; i++) if (trim(lines[i]) == ("- slug: " series)) { s_start = i; break }
    if (!s_start) exit 10
    s_end = n + 1
    for (i = s_start + 1; i <= n; i++) if (lines[i] ~ /^- /) { s_end = i; break }

    # 2. locate the entries: line to insert under
    e_line = 0
    if (group != "") {
      g_start = 0
      for (i = s_start + 1; i < s_end; i++) if (trim(lines[i]) == ("- label: " group)) { g_start = i; break }
      if (!g_start) exit 11
      g_ind = indent(lines[g_start])
      g_end = s_end
      for (i = g_start + 1; i < s_end; i++)
        if (indent(lines[i]) <= g_ind && trim(lines[i]) ~ /^- label:/) { g_end = i; break }
      for (i = g_start + 1; i < g_end; i++) if (trim(lines[i]) == "entries:") { e_line = i; break }
    } else {
      for (i = s_start + 1; i < s_end; i++) if (trim(lines[i]) == "entries:") { e_line = i; break }
    }
    if (!e_line) exit 12

    # 3. entry indent = entries-keyword indent + 2; find last consecutive entry line
    entry_ind = indent(lines[e_line]) + 2
    ins_after = e_line
    for (i = e_line + 1; i <= n; i++) {
      if (lines[i] ~ /^ *- / && indent(lines[i]) == entry_ind) ins_after = i
      else break
    }
    pad = sprintf("%*s", entry_ind, "")

    # 4. emit with insertion
    for (i = 1; i <= n; i++) {
      print lines[i]
      if (i == ins_after) print pad "- " entry
    }
  }
' "$YAML" > "$tmp"
rc=$?

case "$rc" in
  0)  mv "$tmp" "$YAML" ;;
  10) rm -f "$tmp"; soft_fail "series '$SERIES' not found" ;;
  11) rm -f "$tmp"; soft_fail "group '$GROUP' not found in series '$SERIES'" ;;
  12) rm -f "$tmp"; soft_fail "no entries: list found for series '$SERIES'" ;;
  *)  rm -f "$tmp"; soft_fail "awk failed (rc=$rc)" ;;
esac

echo "add-to-series: added $ENTRY to $SERIES${GROUP:+ › $GROUP}" >&2
```

- [ ] **Step 4: Make executable and run test to verify it passes**

```bash
chmod +x scripts/add-to-series.sh
bash tests/test_add_to_series.sh
```
Expected: `Results: 10 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/add-to-series.sh tests/test_add_to_series.sh
git commit -m "feat: add-to-series.sh idempotently inserts entry into series.yml"
```

---

## Task 3: Render `### Series` in issue-comment.sh

**Files:**
- Test: `tests/test_issue_comment_series_render.sh` (create)
- Modify: `scripts/issue-comment.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_issue_comment_series_render.sh`:

```bash
#!/usr/bin/env bash
# Tests that issue-comment.sh renders a ### Series section from a scout-series
# block, and strips that block from the scout-topic fenced block.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Stub `gh`: capture the --body arg into $CAP instead of posting.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
CAP="$STUB/body.txt"
cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--body" ]; then shift; printf '%s' "\$1" > "$CAP"; fi
  shift
done
EOF
chmod +x "$STUB/gh"

run_comment() {
  PATH="$STUB:$PATH" ISSUE_NUMBER=1 GH_TOKEN=x GH_REPO=o/r DEPTH=standard \
    SHARPENED_TOPIC="$1" bash "$REPO_ROOT/scripts/issue-comment.sh"
}

# --- with scout-series block ---
TOPIC=$'A Munich weekend planned around a Michelin anchor.\n```scout-series\n- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich anchor.\n```'
run_comment "$TOPIC"
grep -q '### Series' "$CAP" && pass "series section rendered" || fail "no ### Series section"
grep -qF '- [x] **michelin-weekends**' "$CAP" && pass "checkbox rendered ticked" || fail "checkbox missing"
# block stripped from scout-topic fence: the topic paragraph must NOT contain the fence marker
awk '/```scout-topic/{f=1;next} /```/{f=0} f' "$CAP" | grep -q 'scout-series' \
  && fail "scout-series leaked into scout-topic block" \
  || pass "scout-series stripped from scout-topic block"

# --- without scout-series block: no Series section ---
run_comment "A plain topic with no series."
grep -q '### Series' "$CAP" && fail "unexpected ### Series section" || pass "no series section when absent"
grep -qF '**Start research**' "$CAP" && pass "Start research checkbox still present" || fail "Start research missing"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_issue_comment_series_render.sh`
Expected: FAIL — `no ### Series section` (and likely `scout-series leaked...`).

- [ ] **Step 3: Implement rendering in `issue-comment.sh`**

In `scripts/issue-comment.sh`, after the `SUB_TOPICS_BLOCK` extraction add a `SERIES_BLOCK` extraction:

```bash
# Extract the scout-series fenced block (intent: which series + group).
SERIES_BLOCK="$(printf '%s' "$SHARPENED_TOPIC" | awk '
  /^```scout-series[[:space:]]*$/ { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { exit }
  in_block { print }
')"
```

Extend the `TOPIC_ONLY` awk so it also strips the `scout-series` fence (change the single-block stripper to handle both fence names):

```bash
TOPIC_ONLY="$(printf '%s' "$SHARPENED_TOPIC" | awk '
  /^```scout-subtopics[[:space:]]*$/ { in_block=1; next }
  /^```scout-series[[:space:]]*$/    { in_block=1; next }
  /^```[[:space:]]*$/ && in_block { in_block=0; next }
  !in_block { print }
' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"
```

Build a reusable `SERIES_SECTION` (empty when no block) and inject it into BOTH `body` heredocs
just before the Start checkbox / `### Go` header:

```bash
SERIES_SECTION=""
if [ -n "$SERIES_BLOCK" ]; then
  SERIES_SECTION="$(printf '### Series\n\n%s\n\nThis looks like part of an existing series. Leave it ticked to add this entry to the series when research starts; untick to skip.\n' "$SERIES_BLOCK")"
fi
```

In the **sub-topics** heredoc, insert `${SERIES_SECTION}` between the `### Sub-topics` section and `### Go`. In the **narrow-mode** heredoc, insert `${SERIES_SECTION}` between the `scout-topic` end marker and the `- [ ] **Start research**` line. (When empty, it renders as nothing — no blank `### Series`.)

Implementer note: heredocs expand `${SERIES_SECTION}`; an empty value collapses cleanly. Verify the
blank-line spacing in the rendered output reads well; the test only asserts presence/absence.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_issue_comment_series_render.sh`
Expected: `Results: 6 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/issue-comment.sh tests/test_issue_comment_series_render.sh
git commit -m "feat: render ### Series checkbox in sharpened proposal comment"
```

---

## Task 4: Sharpener emits `scout-series` — sharpen.md + sharpen.sh

**Files:**
- Test: `tests/test_sharpen_series_injection.sh` (create)
- Modify: `scripts/sharpen.sh`, `skills/scout/sharpen.md`

- [ ] **Step 1: Write the failing test (input injection)**

Create `tests/test_sharpen_series_injection.sh` (mirrors `test_sharpen_profile_injection.sh`; stubs `claude` to echo the assembled prompt):

```bash
#!/usr/bin/env bash
# Verify sharpen.sh injects Existing series: and Previous series: blocks.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
last="${!#}"; printf '%s' "$last"
EOF
chmod +x "$STUB/claude"

run() { PATH="$STUB:$PATH" RAW_TOPIC="best ramen" DEPTH=standard \
        SCOUT_PROFILE_FILE=/nonexistent "$@" bash "$REPO_ROOT/scripts/sharpen.sh"; }

# --- manifest present -> Existing series: block injected ---
out=$(SERIES_MANIFEST=$'- slug: michelin-weekends\n  title: Michelin weekends' run) || true
echo "$out" | grep -q "Existing series:" && pass "manifest: block present" || fail "manifest: block missing"
echo "$out" | grep -q "michelin-weekends" && pass "manifest: content passed" || fail "manifest: content missing"

# --- manifest empty/unset -> no Existing series: block ---
out=$(run) || true
echo "$out" | grep -q "Existing series:" && fail "no manifest: unexpected block" || pass "no manifest: no block"

# --- previous series preserved on re-sharpen ---
out=$(PREVIOUS_SERIES=$'- [x] **michelin-weekends** › Germany — Munich.' run) || true
echo "$out" | grep -q "Previous series:" && pass "resharpen: previous block present" || fail "resharpen: previous block missing"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_sharpen_series_injection.sh`
Expected: FAIL — `manifest: block missing` etc.

- [ ] **Step 3: Inject the blocks in `sharpen.sh`**

In `scripts/sharpen.sh`, after the `PREVIOUS_SUB_TOPICS` block and before the profile block, add:

```bash
if [ -n "${PREVIOUS_SERIES:-}" ]; then
  input+="
Previous series:
${PREVIOUS_SERIES}"
fi
if [ -n "${SERIES_MANIFEST:-}" ]; then
  input+="
Existing series:
${SERIES_MANIFEST}"
fi
```

Also document the new optional env in the header comment (`SERIES_MANIFEST`, `PREVIOUS_SERIES`).

- [ ] **Step 4: Run injection test to verify it passes**

Run: `bash tests/test_sharpen_series_injection.sh`
Expected: `Results: 5 passed, 0 failed`

- [ ] **Step 5: Add the skill rule + output format in `sharpen.md`**

Add a new rule under `## Rules` (after rule 8):

```markdown
9. **Series match (only when `Existing series:` is present).** The `Existing series:` block lists
   each series as `slug — title — blurb` plus its group labels. If the sharpened topic *confidently*
   belongs to exactly one of these existing series, append a `scout-series` block (see Output). Be
   conservative — no confident match, emit nothing. Never invent a series that isn't listed. Pick at
   most one series. For a grouped series, pick the single best-fitting group label.
   On a re-sharpen, treat `Previous series:` as the working selection and apply the user's feedback
   as a delta (keep, change group, or drop).
```

Add to `## Output`, after the sub-topics block rules:

````markdown
### Series block format

When rule 9 yields a confident match, append (after any sub-topics block):

```scout-series
- [x] **<series-slug>** › <group-label> — one-line rationale.
```

- Ticked (`- [x]`) by default — it's a suggestion the user can untick.
- `› <group-label>` only for grouped series; omit it entirely for flat series.
- Exactly one line. Omit the whole block when there's no confident match.
````

- [ ] **Step 6: Sanity-run the existing sharpen snapshot test (no regression)**

Run: `bash tests/test_sharpen_snapshots.sh`
Expected: existing behavior unchanged, 0 failed. (These call the prompt assembly / snapshots; the new optional inputs are absent here so output is unchanged.)

- [ ] **Step 7: Commit**

```bash
git add scripts/sharpen.sh skills/scout/sharpen.md tests/test_sharpen_series_injection.sh
git commit -m "feat: sharpener suggests an existing series via scout-series block"
```

---

## Task 5: Wire parse + insert into the research path

**Files:**
- Modify: `scripts/research-from-issue.sh`, `scripts/run.sh`

- [ ] **Step 1: Export series intent in research-from-issue.sh**

In `scripts/research-from-issue.sh`, after the existing `parse_start_choice` / `parse_sub_topics`
calls, add:

```bash
parse_series "$BOT_COMMENT_BODY"   # exports SERIES_SLUG, SERIES_GROUP
```

Ensure both the decompose `exec` and the single-pass `exec` carry the vars. For the single-pass
branch, change the export line to include them:

```bash
export TOPIC RAW_TOPIC DEPTH ISSUE_NUMBER SERIES_SLUG SERIES_GROUP
```

For the decompose branch, add `SERIES_SLUG SERIES_GROUP` to its `export` line as well (forward-compat;
`run-decompose.sh` ignores them in v1).

- [ ] **Step 2: Call add-to-series.sh in run.sh before publish**

In `scripts/run.sh`, immediately before the final `publish.sh` invocation (and after the title-based
slug rename + the `SCOUT_NO_PUBLISH` early-exit), add:

```bash
# Add to an existing Atlas series if the sharpen step suggested one and the
# user left it ticked. Fail-soft: never blocks publishing.
if [ -n "${SERIES_SLUG:-}" ] && [ -n "${ATLAS_DIR:-}" ]; then
  SOFT_FAIL_LOG="$SOFT_FAIL_LOG" \
    bash "$SCOUT_DIR/scripts/add-to-series.sh" \
      "$ATLAS_DIR/_data/series.yml" \
      "${DATE}-${FINAL_SLUG}" \
      "$SERIES_SLUG" "${SERIES_GROUP:-}" \
    || echo "run.sh: add-to-series.sh failed (non-blocking)" >> "$SOFT_FAIL_LOG"
fi
```

Note for implementer: `ATLAS_DIR` is set in the standalone branch of `run.sh` (where Atlas is
cloned). In the decompose-child branch `RESEARCH_DIR` is pre-set and `ATLAS_DIR` is unset — the guard
`[ -n "${ATLAS_DIR:-}" ]` correctly skips those (decompose is out of scope for v1). Confirm `ATLAS_DIR`
is in scope at the insertion point; if it was only a local in the `else` branch, derive it as
`ATLAS_DIR="${ATLAS_DIR:-$(cd "$RESEARCH_DIR/../.." && pwd)}"` guarded to the non-decompose case.

- [ ] **Step 3: Verify the full chain on a fixture (manual integration check)**

```bash
# Simulate: bot comment with a ticked series, then parse + insert into a temp series.yml.
source scripts/lib-issue-parse.sh
parse_series "$(printf '### Series\n- [x] **michelin-weekends** › Germany — x.\n')"
echo "SLUG=$SERIES_SLUG GROUP=$SERIES_GROUP"   # expect: SLUG=michelin-weekends GROUP=Germany
```
Expected: `SLUG=michelin-weekends GROUP=Germany`

- [ ] **Step 4: Run the related unit suites to confirm no regression**

```bash
bash tests/test_lib_issue_parse_series.sh
bash tests/test_lib_issue_parse_subtopics.sh
bash tests/test_rerun_from_issue.sh
```
Expected: all `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/research-from-issue.sh scripts/run.sh
git commit -m "feat: wire series suggestion through research-from-issue and run.sh"
```

---

## Task 6: Fetch the manifest in the workflow + preserve on re-sharpen

**Files:**
- Modify: `.github/workflows/research.yml`

- [ ] **Step 1: Add manifest fetch + env to the sharpen-on-open job**

In `.github/workflows/research.yml`, in the `sharpen-on-open` job's `env:` add the Atlas coordinates:

```yaml
      ATLAS_OWNER: ${{ vars.ATLAS_REPO_OWNER || github.repository_owner }}
      ATLAS_NAME: ${{ vars.ATLAS_REPO_NAME || 'Atlas' }}
```

In the "Sharpen and post proposal" step, before calling `sharpen.sh`, fetch the manifest best-effort
and pass it through:

```bash
          SERIES_MANIFEST="$(curl -fsSL \
            "https://raw.githubusercontent.com/${ATLAS_OWNER}/${ATLAS_NAME}/main/_data/series.yml" \
            2>/dev/null || true)"
          export SERIES_MANIFEST
```

Then in the `else` (non-skip) branch the existing `sharpen.sh` call inherits `SERIES_MANIFEST` from
the environment (no change to the call line needed since it reads env). Confirm the `SHARPENED_TOPIC="$(... bash scripts/sharpen.sh)"` line runs with `SERIES_MANIFEST` exported.

- [ ] **Step 2: Same fetch + PREVIOUS_SERIES extraction in resharpen-on-comment**

In the `resharpen-on-comment` job's `env:` add the same `ATLAS_OWNER` / `ATLAS_NAME`. In the
"Re-sharpen with user feedback" step:

Add the manifest fetch (same `curl` as Step 1, `export SERIES_MANIFEST`).

Extract the prior `### Series` section from `PREVIOUS_BODY` (mirroring `PREVIOUS_SUB_TOPICS`):

```bash
          PREVIOUS_SERIES="$(printf '%s' "$PREVIOUS_BODY" | awk '
            /^### Series[[:space:]]*$/ { in_section=1; next }
            /^### / && in_section { exit }
            in_section { print }
          ' | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"
```

Add `SERIES_MANIFEST="$SERIES_MANIFEST" PREVIOUS_SERIES="$PREVIOUS_SERIES"` to the env prefix of the
`bash scripts/sharpen.sh` call:

```bash
          SHARPENED_TOPIC="$(RAW_TOPIC="$RAW_TOPIC" DEPTH="$DEPTH" \
                             PREVIOUS_SHARPENED="$PREVIOUS_SHARPENED" \
                             PREVIOUS_SUB_TOPICS="$PREVIOUS_SUB_TOPICS" \
                             PREVIOUS_SERIES="$PREVIOUS_SERIES" \
                             SERIES_MANIFEST="$SERIES_MANIFEST" \
                             USER_FEEDBACK="$USER_FEEDBACK" \
                             bash scripts/sharpen.sh)"
```

- [ ] **Step 3: Validate workflow YAML syntax**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/research.yml'))" && echo OK`
Expected: `OK` (no YAML parse error).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/research.yml
git commit -m "feat: fetch Atlas series manifest into the sharpen jobs"
```

---

## Task 7: Final verification

- [ ] **Step 1: Run every new and adjacent test**

```bash
for t in test_lib_issue_parse_series test_add_to_series \
         test_issue_comment_series_render test_sharpen_series_injection \
         test_lib_issue_parse_subtopics test_sharpen_profile_injection \
         test_rerun_from_issue; do
  echo "== $t =="; bash "tests/$t.sh" || exit 1
done
echo "ALL GREEN"
```
Expected: `ALL GREEN`.

- [ ] **Step 2: Confirm `add-to-series.sh` is executable and committed**

Run: `git ls-files -s scripts/add-to-series.sh`
Expected: mode `100755`.

- [ ] **Step 3: Re-read the spec, confirm coverage**

Open `docs/superpowers/specs/2026-05-30-series-suggestion-design.md`; confirm each numbered flow step
(1 sharpen, 2 render, 3 re-sharpen, 4 parse, 5 YAML edit) maps to a task above. Decompose path is
explicitly out of scope.

---

## Self-Review Notes

- **Spec coverage:** Flow §1→Task 4/6, §2→Task 3, §3→Task 6, §4→Task 1/5, §5→Task 2/5. Tests table in spec → Tasks 1–4. ✓
- **Type/name consistency:** `SERIES_SLUG`/`SERIES_GROUP` (parse), `SERIES_MANIFEST`/`PREVIOUS_SERIES` (sharpen), `scout-series` fence, `### Series` section, exit codes 10/11/12 — used identically across tasks. ✓
- **No placeholders:** every code step shows real code; awk insert + parse regex are complete (with documented fallback notes where bash-ERE edge cases may need iteration against the pinned tests).
