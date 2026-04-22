#!/usr/bin/env bash
# Tests for scripts/inject_cost.sh. Run: bash tests/test_inject_cost.sh

REPO_ROOT="$(git rev-parse --show-toplevel)"
INJECTOR="$REPO_ROOT/scripts/inject_cost.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/artifacts"

PASS=0
FAIL=0
declare -a FAIL_MSGS

fail() {
  FAIL_MSGS+=("$1")
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

run_on_copy() {
  # Copies fixture to a tmp path, invokes injector. Echoes tmp path.
  local fixture="$1"; shift
  local cost="$1"; shift
  local duration="$1"; shift
  local tmp
  tmp=$(mktemp --suffix=".${fixture##*.}")
  cp "$FIXTURES/$fixture" "$tmp"
  "$INJECTOR" "$tmp" "$cost" "$duration" > /dev/null 2>&1
  local rc=$?
  echo "$tmp $rc"
}

echo "Testing inject_cost.sh..."

# --- happy path, markdown ---
read tmp rc < <(run_on_copy valid.md 0.43 287)
if [ "$rc" = "0" ]; then
  if grep -q "^cost_usd: 0.43$" "$tmp" && grep -q "^duration_sec: 287$" "$tmp"; then
    # fields must sit inside the frontmatter block, not in the body
    end_fm_line=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$tmp")
    cost_line=$(awk '/^cost_usd:/{print NR; exit}' "$tmp")
    if [ -n "$end_fm_line" ] && [ -n "$cost_line" ] && [ "$cost_line" -lt "$end_fm_line" ]; then
      pass "md: injects fields inside frontmatter"
    else
      fail "md: injected fields not inside frontmatter block"
    fi
  else
    fail "md: expected fields not found in output"
  fi
  # body must be untouched
  if grep -q "^## Body$" "$tmp" && grep -q "^Some content here.$" "$tmp"; then
    pass "md: body untouched"
  else
    fail "md: body was altered"
  fi
else
  fail "md: injector exited non-zero on valid input (rc=$rc)"
fi
rm -f "$tmp"

# --- happy path, html ---
read tmp rc < <(run_on_copy valid.html 1.25 612)
if [ "$rc" = "0" ] && grep -q "^cost_usd: 1.25$" "$tmp" && grep -q "^duration_sec: 612$" "$tmp"; then
  pass "html: injects fields into frontmatter"
else
  fail "html: expected fields missing or exit non-zero (rc=$rc)"
fi
rm -f "$tmp"

# --- failure: no frontmatter ---
read tmp rc < <(run_on_copy no_frontmatter.md 0.10 30)
if [ "$rc" = "1" ]; then
  pass "no frontmatter: fails with exit 1"
else
  fail "no frontmatter: expected exit 1, got $rc"
fi
rm -f "$tmp"

# --- failure: unterminated frontmatter ---
read tmp rc < <(run_on_copy unterminated_frontmatter.md 0.10 30)
if [ "$rc" = "1" ]; then
  pass "unterminated frontmatter: fails with exit 1"
else
  fail "unterminated frontmatter: expected exit 1, got $rc"
fi
rm -f "$tmp"

# --- failure: missing file ---
"$INJECTOR" "/nonexistent/path.md" 0.1 30 > /dev/null 2>&1
rc=$?
if [ "$rc" = "1" ]; then
  pass "missing file: fails with exit 1"
else
  fail "missing file: expected exit 1, got $rc"
fi

# --- failure: wrong arg count ---
"$INJECTOR" "$FIXTURES/valid.md" > /dev/null 2>&1
rc=$?
if [ "$rc" = "1" ]; then
  pass "missing args: fails with exit 1"
else
  fail "missing args: expected exit 1, got $rc"
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
