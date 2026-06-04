#!/usr/bin/env bash
# Tests for scripts/backfill-metadata.sh — truthfully backfills missing
# model/duration_sec/cost_usd into legacy research frontmatter from each node's
# .scout-result.json, touching only fields the triage scanner flags as MISSING_*.
# Run: bash tests/test_backfill_metadata.sh

REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKFILL="$REPO_ROOT/scripts/backfill-metadata.sh"
SCAN="$REPO_ROOT/skills/scout-triage/scan.py"

PASS=0; FAIL=0; declare -a FAIL_MSGS
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }

echo "Testing backfill-metadata.sh..."

ROOT="$(mktemp -d)"; RES="$ROOT/research"; mkdir -p "$RES"
BODY="$(printf 'lorem ipsum dolor sit amet consectetur %.0s' {1..40})"  # >600 chars = "real"

# Synthetic result JSON: opus-4-7 did the most output work; haiku is a side-call.
result_json() {  # $1=cost $2=duration_ms
  printf '{"total_cost_usd": %s, "duration_ms": %s, "modelUsage": {' "$1" "$2"
  printf '"claude-haiku-4-5-20251001": {"outputTokens": 120},'
  printf '"claude-opus-4-7[1m]": {"outputTokens": 9000}}}'
}

# Case 1: missing model only (cost + duration already present) + result JSON.
mkdir -p "$RES/2026-01-01-model-only"
printf -- '---\ntitle: "M"\ncost_usd: 1.23\nduration_sec: 99\ncover: cover.svg\n---\n%s\n' "$BODY" \
  > "$RES/2026-01-01-model-only/index.md"
printf '<svg/>' > "$RES/2026-01-01-model-only/cover.svg"
result_json 1.23 99000 > "$RES/2026-01-01-model-only/.scout-result.json"

# Case 2: missing all three + result JSON.
mkdir -p "$RES/2026-01-02-all-three"
printf -- '---\ntitle: "A"\ncover: cover.svg\n---\n%s\n' "$BODY" \
  > "$RES/2026-01-02-all-three/index.md"
printf '<svg/>' > "$RES/2026-01-02-all-three/cover.svg"
result_json 4.51 612000 > "$RES/2026-01-02-all-three/.scout-result.json"

# Case 3: missing model, NO result JSON -> must stay untouched (genuinely lost).
mkdir -p "$RES/2026-01-03-lost"
printf -- '---\ntitle: "L"\ncost_usd: 2.0\nduration_sec: 50\ncover: cover.svg\n---\n%s\n' "$BODY" \
  > "$RES/2026-01-03-lost/index.md"
printf '<svg/>' > "$RES/2026-01-03-lost/cover.svg"

"$BACKFILL" "$RES" > /dev/null 2>&1

A1="$RES/2026-01-01-model-only/index.md"
# model injected with correct friendly label
grep -q '^model: "Opus 4.7"$' "$A1" \
  && pass "model-only: injects friendly model label" || fail "model-only: model label not injected"
# cost/duration NOT duplicated (exactly one each)
[ "$(grep -c '^cost_usd:' "$A1")" = "1" ] && [ "$(grep -c '^duration_sec:' "$A1")" = "1" ] \
  && pass "model-only: no duplicate cost/duration lines" || fail "model-only: duplicated existing fields"
# original values preserved
grep -q '^cost_usd: 1.23$' "$A1" && grep -q '^duration_sec: 99$' "$A1" \
  && pass "model-only: leaves existing values intact" || fail "model-only: clobbered existing values"

A2="$RES/2026-01-02-all-three/index.md"
grep -q '^model: "Opus 4.7"$' "$A2" \
  && grep -q '^cost_usd: 4.51$' "$A2" \
  && grep -q '^duration_sec: 612$' "$A2" \
  && pass "all-three: injects model + cost + duration from result" \
  || fail "all-three: missing one of model/cost/duration"

A3="$RES/2026-01-03-lost/index.md"
grep -q '^model:' "$A3" \
  && fail "lost: must not inject model without a result JSON" \
  || pass "lost: untouched when no .scout-result.json"

# After backfill, scanner reports zero MISSING_MODEL/DURATION/COST for the two fixed nodes.
HEALTH="$(SCOUT_HEALTH_GENERATED=T python3 "$SCAN" --health "$RES")"
flagged="$(jq -r '[.hygiene[] | select(.slug=="2026-01-01-model-only" or .slug=="2026-01-02-all-three")
                  | .items[].findings[].category
                  | select(.=="MISSING_MODEL" or .=="MISSING_DURATION" or .=="MISSING_COST")] | length' <<<"$HEALTH")"
[ "$flagged" = "0" ] \
  && pass "backfilled nodes no longer flagged by scanner" || fail "scanner still flags backfilled nodes ($flagged)"
# lost node is still flagged (honestly)
jq -e '.hygiene[] | select(.slug=="2026-01-03-lost") | .items[].findings | map(.category) | index("MISSING_MODEL")' \
  <<<"$HEALTH" >/dev/null \
  && pass "lost node still honestly flagged MISSING_MODEL" || fail "lost node should remain flagged"

# Idempotent: a second run injects nothing new.
"$BACKFILL" "$RES" > /dev/null 2>&1
[ "$(grep -c '^model:' "$A1")" = "1" ] \
  && pass "idempotent: re-run does not duplicate injected fields" || fail "idempotent: re-run duplicated fields"

rm -rf "$ROOT"
echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
