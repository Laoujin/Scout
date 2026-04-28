#!/usr/bin/env bash
# Tests for scripts/validate_ledger.sh. Run: bash tests/test_validate_ledger.sh

REPO_ROOT="$(git rev-parse --show-toplevel)"
VALIDATOR="$REPO_ROOT/scripts/validate_ledger.sh"
FIXTURES="$REPO_ROOT/tests/fixtures/ledgers"

PASS=0
FAIL=0
declare -a FAIL_MSGS

run_test() {
  local name="$1"
  local expected_status="$2"
  local expected_stderr_sub="$3"
  shift 3
  # Remaining args are passed to the validator (ledger [artifact])

  local err_file
  err_file=$(mktemp)
  "$VALIDATOR" "$@" > /dev/null 2> "$err_file"
  local actual_status=$?
  local actual_stderr
  actual_stderr=$(cat "$err_file")
  rm -f "$err_file"

  if [ "$actual_status" = "$expected_status" ]; then
    if [ -z "$expected_stderr_sub" ] || [[ "$actual_stderr" == *"$expected_stderr_sub"* ]]; then
      echo "  PASS: $name"
      PASS=$((PASS + 1))
      return
    fi
    FAIL_MSGS+=("$name: stderr missing '$expected_stderr_sub'; got: $actual_stderr")
  else
    FAIL_MSGS+=("$name: expected exit $expected_status, got $actual_status; stderr: $actual_stderr")
  fi
  echo "  FAIL: $name"
  FAIL=$((FAIL + 1))
}

echo "Testing validate_ledger.sh..."

# --- Ledger-only tests --------------------------------------------------------
run_test "valid ledger passes"        0 ""              "$FIXTURES/valid.jsonl"
run_test "empty url fails"            1 "empty url"     "$FIXTURES/invalid_empty_url.jsonl"
run_test "duplicate url fails"        1 "duplicate"     "$FIXTURES/invalid_duplicate_url.jsonl"
run_test "missing source_type fails"  1 "source_type"   "$FIXTURES/invalid_missing_source_type.jsonl"
run_test "missing file fails loudly"  1 ""              "$FIXTURES/does_not_exist.jsonl"

# --- Artifact resolution tests ------------------------------------------------
TMPDIR_ART="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ART"' EXIT

# HTML artifact with NO [[n]] markers (e.g. inline citations) — must not crash.
cat > "$TMPDIR_ART/html_no_markers.html" <<'HTML'
---
title: Test research
---
<html><body>
<p>Some research with <a href="https://example.com">inline citations</a>.</p>
</body></html>
HTML

# Markdown artifact with [[n]] markers in bounds.
cat > "$TMPDIR_ART/md_in_bounds.md" <<'MD'
---
title: Test
---
This references [[1]] and [[2]] which are in the ledger.
MD

# Markdown artifact with [[n]] marker out of bounds.
cat > "$TMPDIR_ART/md_out_of_bounds.md" <<'MD'
---
title: Test
---
This references [[1]] and [[99]] which exceeds the ledger.
MD

run_test "HTML with no markers passes"          0 ""       "$FIXTURES/valid.jsonl" "$TMPDIR_ART/html_no_markers.html"
run_test "markers in bounds passes"             0 ""       "$FIXTURES/valid.jsonl" "$TMPDIR_ART/md_in_bounds.md"
run_test "markers out of bounds fails"          1 "beyond" "$FIXTURES/valid.jsonl" "$TMPDIR_ART/md_out_of_bounds.md"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
