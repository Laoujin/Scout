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

echo "Testing sharpen_snapshots.sh..."

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
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
