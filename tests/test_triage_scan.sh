#!/usr/bin/env bash
# Tests for skills/scout-triage/scan.py — severity tagging + --health grouping.
# Run: bash tests/test_triage_scan.sh

REPO_ROOT="$(git rev-parse --show-toplevel)"
SCAN="$REPO_ROOT/skills/scout-triage/scan.py"

PASS=0; FAIL=0; declare -a FAIL_MSGS
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }

echo "Testing scout-triage scan.py..."

ROOT="$(mktemp -d)"; RES="$ROOT/research"; mkdir -p "$RES"
BODY="$(printf 'lorem ipsum dolor sit amet consectetur %.0s' {1..40})"  # >600 chars = "real"

# critical: single-pass leaf, tiny body + failure marker -> GENUINE_FAILURE
mkdir -p "$RES/2026-01-01-failed"
printf -- '---\ntitle: "F"\n---\nResearch failed: child run.sh exit 1\n' > "$RES/2026-01-01-failed/index.md"

# hygiene: real leaf, cost_usd:sub + cover, but missing model + duration
mkdir -p "$RES/2026-01-02-hygiene"
printf -- '---\ntitle: "H"\ncost_usd: "sub"\ncover: cover.svg\n---\n%s\n' "$BODY" > "$RES/2026-01-02-hygiene/index.md"
printf '<svg/>' > "$RES/2026-01-02-hygiene/cover.svg"

# clean: real leaf with all metadata + cover -> no findings
mkdir -p "$RES/2026-01-03-clean"
printf -- '---\ntitle: "C"\nmodel: "Opus 4.8"\nduration_sec: 5\ncost_usd: "sub"\ncover: cover.svg\n---\n%s\n' "$BODY" > "$RES/2026-01-03-clean/index.md"
printf '<svg/>' > "$RES/2026-01-03-clean/cover.svg"

HEALTH="$(SCOUT_HEALTH_GENERATED=T python3 "$SCAN" --health "$RES")"
JSON="$(python3 "$SCAN" --json "$RES")"

[ "$(jq '.counts.critical' <<<"$HEALTH")" = "1" ] \
  && pass "one critical research" || fail "expected counts.critical=1, got $(jq '.counts.critical' <<<"$HEALTH")"

jq -e '.critical[] | select(.slug=="2026-01-01-failed")' <<<"$HEALTH" >/dev/null \
  && pass "failed research in critical tier" || fail "failed research not in critical tier"

jq -e '.hygiene[] | select(.slug=="2026-01-02-hygiene")' <<<"$HEALTH" >/dev/null \
  && pass "hygiene research in hygiene tier" || fail "hygiene research not in hygiene tier"

if jq -e '[.critical[],.hygiene[]] | map(.slug) | index("2026-01-03-clean")' <<<"$HEALTH" >/dev/null; then
  fail "clean research should not appear in any tier"
else
  pass "clean research absent from both tiers"
fi

jq -e '.hygiene[] | select(.slug=="2026-01-02-hygiene") | .items[0].findings | map(.category)
       | (index("MISSING_MODEL") and index("MISSING_DURATION"))' <<<"$HEALTH" >/dev/null \
  && pass "hygiene leaf flags MISSING_MODEL + MISSING_DURATION" || fail "hygiene leaf missing expected categories"

[ "$(jq '[.[] | has("severity")] | all' <<<"$JSON")" = "true" ] \
  && pass "every finding has a severity field" || fail "some findings lack severity"

[ "$(jq -r '.[] | select(.category=="GENUINE_FAILURE") | .severity' <<<"$JSON" | head -1)" = "critical" ] \
  && pass "GENUINE_FAILURE tagged critical" || fail "GENUINE_FAILURE not tagged critical"

[ "$(jq '[.[] | select(.category=="MISSING_ISSUE")] | length' <<<"$JSON")" = "0" ] \
  && pass "cost_usd:sub runs exempt from MISSING_ISSUE" || fail "sub run wrongly flagged MISSING_ISSUE"

rm -rf "$ROOT"
echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
