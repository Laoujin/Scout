#!/usr/bin/env bash
# Unit tests for profile injection in scripts/sharpen.sh.
# Stubs `claude` with a script that prints its last positional arg
# (which is the prompt $input that sharpen.sh assembles), so we can
# inspect exactly what sharpen.sh would have sent.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$REPO_ROOT/tests/fixtures/profile"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing sharpen.sh profile injection..."

# Build a stub claude that prints the last positional arg verbatim.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Prints only the final positional arg (the user prompt).
last="${!#}"
printf '%s' "$last"
EOF
chmod +x "$STUB_DIR/claude"

run_sharpen() {
  # Args: $1=profile_file_path (or "" for unset), $2=raw_topic
  local profile_file="$1" raw="$2"
  if [ -n "$profile_file" ]; then
    PATH="$STUB_DIR:$PATH" \
      RAW_TOPIC="$raw" DEPTH=standard \
      SCOUT_PROFILE_FILE="$profile_file" \
      bash "$REPO_ROOT/scripts/sharpen.sh"
  else
    PATH="$STUB_DIR:$PATH" \
      RAW_TOPIC="$raw" DEPTH=standard \
      SCOUT_PROFILE_FILE=/nonexistent/path/to/profile.yml \
      bash "$REPO_ROOT/scripts/sharpen.sh"
  fi
}

# --- Case 1: profile file does not exist ---
out=$(run_sharpen "" "best ramen") || true
echo "$out" | grep -q "User profile:" \
  && fail "case 1 (missing file): unexpected 'User profile:' block in input" \
  || pass "case 1 (missing file): no 'User profile:' block"
echo "$out" | grep -q "best ramen" \
  && pass "case 1 (missing file): raw topic preserved" \
  || fail "case 1 (missing file): raw topic missing from input"

# --- Case 2: profile file exists but is empty (0 bytes) ---
out=$(run_sharpen "$FIXTURES/empty.yml" "best ramen") || true
echo "$out" | grep -q "User profile:" \
  && fail "case 2 (empty file): unexpected 'User profile:' block" \
  || pass "case 2 (empty file): no 'User profile:' block"

# --- Case 3: comment-only profile (installer skeleton) ---
out=$(run_sharpen "$FIXTURES/comment-only.yml" "best ramen") || true
echo "$out" | grep -q "User profile:" \
  && pass "case 3 (comment-only): 'User profile:' block present" \
  || fail "case 3 (comment-only): 'User profile:' block missing"
echo "$out" | grep -q "Until you add fields below" \
  && pass "case 3 (comment-only): skeleton comment passed through" \
  || fail "case 3 (comment-only): skeleton comment missing from input"

# --- Case 4: populated profile ---
out=$(run_sharpen "$FIXTURES/populated.yml" "best ramen") || true
echo "$out" | grep -q "User profile:" \
  && pass "case 4 (populated): 'User profile:' block present" \
  || fail "case 4 (populated): 'User profile:' block missing"
echo "$out" | grep -q "Ghent, Belgium" \
  && pass "case 4 (populated): location field passed through" \
  || fail "case 4 (populated): location field missing from input"
echo "$out" | grep -q "currency: EUR" \
  && pass "case 4 (populated): currency field passed through" \
  || fail "case 4 (populated): currency field missing from input"

# --- Case 5: ordering — User profile: comes after Depth: line ---
if echo "$out" | grep -q "User profile:"; then
  depth_line=$(echo "$out" | grep -n "^Depth:" | cut -d: -f1)
  profile_line=$(echo "$out" | grep -n "^User profile:" | cut -d: -f1)
  if [ -n "$depth_line" ] && [ -n "$profile_line" ] && [ "$profile_line" -gt "$depth_line" ]; then
    pass "case 5 (ordering): 'User profile:' appears after 'Depth:'"
  else
    fail "case 5 (ordering): expected User profile: line ($profile_line) > Depth: line ($depth_line)"
  fi
fi

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
