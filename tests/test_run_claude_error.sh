#!/usr/bin/env bash
# Tests that run.sh surfaces a Claude `is_error` result clearly instead of
# silently proceeding: it writes RESEARCH_DIR/.scout-error with a human reason
# and (when nothing was salvageable) exits non-zero. This is what lets the
# decompose parent annotate "ran out of tokens" instead of "child run.sh exit 1".

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run.sh Claude-error handling..."

# Build an isolated scout dir with a stub `claude` on PATH. The stub emits a
# JSON result; whether it writes an artifact is controlled by STUB_WRITE_ARTIFACT.
setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/scout/skills/scout"
  for s in run.sh slug.sh lib-models.sh validate_frontmatter.sh validate_ledger.sh inject_cost.sh; do
    cp "$REPO_ROOT/scripts/$s" "$tmp/scout/scripts/"
  done
  cp "$REPO_ROOT/skills/scout/SKILL.md" "$tmp/scout/skills/scout/"

  cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
if [ "${STUB_WRITE_ARTIFACT:-0}" = "1" ]; then
  cat > "$RESEARCH_DIR/index.md" <<MD
---
title: "Partial but real"
date: 2026-05-29
depth: ceo
format: md
citations: 0
reading_time_min: 1
---
Body with real content.
MD
fi
cat "$STUB_RESULT_JSON"
STUB
  chmod +x "$tmp/claude"
  echo "$tmp"
}

run_child() {
  # Runs run.sh in decompose-child mode (no clone, no publish) with the stub.
  local tmp="$1"
  PATH="$tmp:$PATH" \
    env TOPIC="t" RAW_TOPIC="t" DEPTH="ceo" FORMAT="md" \
        RESEARCH_DIR="$tmp/research" \
        SCOUT_DECOMPOSE_CHILD=1 SCOUT_NO_PUBLISH=1 \
        STUB_RESULT_JSON="$tmp/result.json" \
        STUB_WRITE_ARTIFACT="${STUB_WRITE_ARTIFACT:-0}" \
        bash "$tmp/scout/scripts/run.sh" >/dev/null 2>"$tmp/stderr.log"
}

# --- Case 1: is_error, no artifact → clear .scout-error + non-zero exit ---
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"is_error":true,"subtype":"error_during_execution","result":"Claude AI usage limit reached","total_cost_usd":0,"duration_ms":0}
JSON
STUB_WRITE_ARTIFACT=0 run_child "$tmp"; rc=$?
[ "$rc" -ne 0 ] && pass "is_error + no artifact exits non-zero" || fail "should exit non-zero on is_error with no artifact (got $rc)"
[ -s "$tmp/research/.scout-error" ] && pass ".scout-error written" || fail ".scout-error missing"
grep -qi "usage" "$tmp/research/.scout-error" 2>/dev/null \
  && pass ".scout-error names the usage limit" \
  || fail ".scout-error should mention the usage limit (got: $(cat "$tmp/research/.scout-error" 2>/dev/null))"
rm -rf "$tmp"

# --- Case 2: is_error WITH a real artifact (decompose child) ---
# Child still exits non-zero so the parent classifies it as error_with_content
# (using .scout-error as the reason) rather than a clean success; the artifact
# is left on disk for the parent to salvage and annotate.
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"is_error":true,"subtype":"error_max_turns","result":"hit max turns","total_cost_usd":0.5,"duration_ms":2000}
JSON
STUB_WRITE_ARTIFACT=1 run_child "$tmp"; rc=$?
[ "$rc" -ne 0 ] && pass "is_error child exits non-zero even with artifact" || fail "child should exit non-zero on is_error (got $rc)"
[ -s "$tmp/research/.scout-error" ] && pass ".scout-error kept for salvageable run" || fail ".scout-error should still be written when salvaging"
[ -f "$tmp/research/index.md" ] && pass "artifact preserved on disk for parent" || fail "artifact should be preserved"
rm -rf "$tmp"

# --- Case 3: clean success → no .scout-error ---
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"is_error":false,"subtype":"success","result":"done","total_cost_usd":0.3,"duration_ms":1500}
JSON
STUB_WRITE_ARTIFACT=1 run_child "$tmp"; rc=$?
[ "$rc" -eq 0 ] && pass "clean success exits 0" || fail "clean success should exit 0 (got $rc)"
[ ! -f "$tmp/research/.scout-error" ] && pass "no .scout-error on success" || fail ".scout-error should not exist on success"
rm -rf "$tmp"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
