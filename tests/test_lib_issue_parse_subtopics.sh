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

echo "Testing lib_issue_parse_subtopics.sh..."

# --- canonical sub-topic line ---
COMMENT=$'### Sub-topics\n- [x] (expedition) **Routing** — Wildcard TLS.\n- [ ] (recon) **Glue** — Orchestration angle.\n\n### Go\n- [ ] **Start research**\n- [ ] **Research as one expedition instead**\n'
parse_sub_topics "$COMMENT"
assert_eq "canonical: count" "2" "${#SUB_TOPICS[@]}"
assert_eq "canonical: line0 checked" "true"        "${SUB_TOPICS[0]##*|}"
assert_eq "canonical: line0 depth"   "deep"        "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "canonical: line0 title"   "Routing"     "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f1)"
assert_eq "canonical: line1 checked" "false"       "${SUB_TOPICS[1]##*|}"
assert_eq "canonical: line1 depth"   "ceo"         "$(echo "${SUB_TOPICS[1]}" | cut -d'|' -f2)"

# --- Issue 1 regression: pipe in title/rationale stripped to keep delimited format intact ---
COMMENT=$'### Sub-topics\n- [x] (survey) **Title|with|pipes** — rat|ionale.\n'
parse_sub_topics "$COMMENT"
assert_eq "pipe-strip: title"        "Titlewithpipes"  "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f1)"
assert_eq "pipe-strip: depth"        "standard"        "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "pipe-strip: rationale"    "rationale."      "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f3)"

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
assert_eq "asterisk bullet title"        "Asterisk" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f1)"

# --- absent Sub-topics section -> empty array ---
COMMENT=$'### Go\n- [ ] **Start research**\n'
parse_sub_topics "$COMMENT"
assert_eq "absent section: empty"        "0"        "${#SUB_TOPICS[@]}"

# --- Issue 24 regression: literal * inside bold title (e.g. *.domain) ---
COMMENT=$'### Sub-topics\n- [x] (expedition) **Per-feature subdomain routing on `*.sangu.be`** \xe2\x80\x94 Wildcard reverse proxy on Synology.\n'
parse_sub_topics "$COMMENT"
assert_eq "asterisk-in-title: count"     "1"        "${#SUB_TOPICS[@]}"
assert_eq "asterisk-in-title: title"     "Per-feature subdomain routing on \`*.sangu.be\`" "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f1)"
assert_eq "asterisk-in-title: depth"     "deep"     "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "asterisk-in-title: rationale" "Wildcard reverse proxy on Synology." "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f3)"

# --- integration-shape: full real bot-comment body ---
COMMENT="$(cat <<'BODY_EOF'
### Sharpened proposal

> Para about Slack and Synology.

<!-- scout-topic-start -->
```scout-topic
Para about Slack and Synology.
```
<!-- scout-topic-end -->

This topic has several independent angles. The list below is informational for now — Start research will run a single expedition over the whole topic. (Per-angle decomposition is being wired in a follow-up.)

### Sub-topics

- [ ] (expedition) **Slack remote control** — Per-channel agents.
- [x] (survey) **Branch automation** — How "go" produces a branch.
- [ ] (recon) **Glue** — Orchestration angle.

### Go

- [ ] **Start research** — tick this to publish to Atlas (depth: `expedition`, format: `auto`).

Not what you wanted? Reply with feedback and I'll propose a new sharpened version.
BODY_EOF
)"
parse_sub_topics "$COMMENT"
assert_eq "integration: count"           "3"        "${#SUB_TOPICS[@]}"
assert_eq "integration: line0 depth"     "deep"     "$(echo "${SUB_TOPICS[0]}" | cut -d'|' -f2)"
assert_eq "integration: line1 checked"   "true"     "${SUB_TOPICS[1]##*|}"
assert_eq "integration: line2 title"     "Glue"     "$(echo "${SUB_TOPICS[2]}" | cut -d'|' -f1)"
# Start research is in the body but we only consume Sub-topics section content
parse_start_choice "$COMMENT"
assert_eq "integration: start choice"    "none"     "$START_CHOICE"   # none ticked

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
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
