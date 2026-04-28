#!/usr/bin/env bash
# Tests for scripts/slug.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/slug.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1: expected '$2', got '$3'"; }
assert_le() { [ "$2" -le "$3" ] && pass "$1" || fail "$1: expected <= $3, got $2"; }

echo "Testing slug.sh..."

# --- basic slugification ---
assert_eq "simple"       "hello-world"  "$(slugify "Hello World")"
assert_eq "special chars" "foo-bar-baz" "$(slugify "foo@bar!baz")"
assert_eq "collapse dash" "a-b"         "$(slugify "a---b")"
assert_eq "trim dashes"   "abc"         "$(slugify "--abc--")"

# --- truncation at default 120 ---
LONG="$(printf 'word%.0s-' {1..200})"
result="$(slugify "$LONG")"
assert_le "default max 120" "${#result}" 120

# --- truncation with explicit max_len ---
result="$(slugify "$LONG" 60)"
assert_le "explicit max 60" "${#result}" 60

# --- no trailing dash after truncation ---
result="$(slugify "$LONG")"
[[ "$result" != *- ]] && pass "no trailing dash" || fail "trailing dash in: $result"

# --- long single token (no dashes to cut at) ---
MONO="$(printf 'a%.0s' {1..300})"
result="$(slugify "$MONO")"
assert_le "single-token truncation" "${#result}" 120
[ -n "$result" ] && pass "single-token non-empty" || fail "single-token produced empty slug"

# --- SLUG_MAX_LENGTH env override ---
SLUG_MAX_LENGTH=40 result="$(slugify "$LONG")"
assert_le "env override 40" "${#result}" 40

# --- real-world long topic (the bug that prompted this) ---
TOPIC="Smoke-test brief: verifying the decompose pipeline by running three unrelated decision-only fact lookups in 2026 with one citation each: (1) the current stable Bun version and its 2026 release date, (2) the current stable Caddy version and which ACME challenge type it defaults to in 2026, and (3) the current stable ripgrep version available via Homebrew in 2026. These are unrelated fact lookups; don't merge them into one survey."
result="$(slugify "$TOPIC")"
assert_le "real-world topic" "${#result}" 120
[ -n "$result" ] && pass "real-world non-empty" || fail "real-world produced empty slug"

# --- short strings are unchanged ---
assert_eq "short unchanged" "hello" "$(slugify "hello")"
assert_eq "empty input"     ""      "$(slugify "")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  for msg in "${FAIL_MSGS[@]}"; do echo "  FAIL: $msg"; done
  exit 1
fi
