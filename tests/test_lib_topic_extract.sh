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
