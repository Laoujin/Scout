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
  local ledger_arg="$4"

  local err_file
  err_file=$(mktemp)
  "$VALIDATOR" "$ledger_arg" > /dev/null 2> "$err_file"
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
run_test "valid ledger passes"        0 ""              "$FIXTURES/valid.jsonl"
run_test "empty url fails"            1 "empty url"     "$FIXTURES/invalid_empty_url.jsonl"
run_test "duplicate url fails"        1 "duplicate"     "$FIXTURES/invalid_duplicate_url.jsonl"
run_test "missing source_type fails"  1 "source_type"   "$FIXTURES/invalid_missing_source_type.jsonl"
run_test "missing file fails loudly"  1 ""              "$FIXTURES/does_not_exist.jsonl"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
