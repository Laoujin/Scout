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

# --- Case 1b: Claude exits non-zero but still writes is_error JSON ---
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"type":"result","subtype":"success","is_error":true,"api_error_status":529,"result":"API Error: 529 Overloaded","total_cost_usd":0,"duration_ms":0}
JSON
cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_RESULT_JSON"
exit 1
STUB
chmod +x "$tmp/claude"
STUB_WRITE_ARTIFACT=0 run_child "$tmp"; rc=$?
[ "$rc" -ne 0 ] && pass "non-zero Claude exit still exits non-zero" || fail "should exit non-zero when Claude exits 1 with is_error JSON (got $rc)"
[ -s "$tmp/research/.scout-error" ] && pass ".scout-error written for non-zero Claude exit" || fail ".scout-error missing when Claude exits 1 with result JSON"
grep -qi "api status 529" "$tmp/research/.scout-error" 2>/dev/null \
  && pass ".scout-error keeps the Claude API status" \
  || fail ".scout-error should include api status 529 (got: $(cat "$tmp/research/.scout-error" 2>/dev/null))"
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

# --- Case 4: agent orphans .scout-result.json mid-run → still succeeds ---
# Regression (2026-06-03): a child agent runs in RESEARCH_DIR with
# --dangerously-skip-permissions; an over-eager model git-cleaned the untracked
# result file, so run.sh's `jq .result` read it as "No such file" and the child
# was wrongly flagged error_with_content. run.sh must capture the result OUTSIDE
# the working tree and ship it regardless of what the agent does in RESEARCH_DIR.
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"is_error":false,"subtype":"success","result":"done","total_cost_usd":0.4,"duration_ms":1200}
JSON
cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: "Real"
date: 2026-05-29
depth: ceo
format: md
citations: 0
reading_time_min: 1
---
Body.
MD
cat "$STUB_RESULT_JSON"
# Simulate the agent wiping untracked dotfiles in its own working dir.
rm -f "$RESEARCH_DIR/.scout-result.json"
STUB
chmod +x "$tmp/claude"
STUB_WRITE_ARTIFACT=1 run_child "$tmp"; rc=$?
[ "$rc" -eq 0 ] && pass "survives agent orphaning the result file" || fail "should exit 0 when agent removes .scout-result.json (got $rc)"
[ ! -f "$tmp/research/.scout-error" ] && pass "no .scout-error when result orphaned but artifact good" || fail ".scout-error should not be written (got: $(cat "$tmp/research/.scout-error" 2>/dev/null))"
[ -s "$tmp/research/.scout-result.json" ] && pass "result JSON re-shipped from protected temp" || fail ".scout-result.json should be shipped from the temp"
rm -rf "$tmp"

# --- Case 5: GitHub auth stripped from the agent's env ---
# The agent's only job is to write files; run.sh owns publishing. If the agent
# can authenticate gh it posts its own (wrong, 404) "Published:" comments, so
# run.sh must strip GH auth before invoking claude.
tmp=$(setup)
cat > "$tmp/result.json" <<'JSON'
{"is_error":false,"subtype":"success","result":"done","total_cost_usd":0.1,"duration_ms":500}
JSON
cat > "$tmp/claude" <<'STUB'
#!/usr/bin/env bash
{ echo "GH_TOKEN=[${GH_TOKEN:-UNSET}]"; echo "GITHUB_TOKEN=[${GITHUB_TOKEN:-UNSET}]"; } > "$RESEARCH_DIR/gh-env.txt"
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: "Real"
date: 2026-05-29
depth: ceo
format: md
citations: 0
reading_time_min: 1
---
Body.
MD
cat "$STUB_RESULT_JSON"
STUB
chmod +x "$tmp/claude"
GH_TOKEN=secret GITHUB_TOKEN=secret2 STUB_WRITE_ARTIFACT=1 run_child "$tmp"; rc=$?
grep -q 'GH_TOKEN=\[UNSET\]' "$tmp/research/gh-env.txt" 2>/dev/null \
  && pass "GH_TOKEN stripped from agent env" \
  || fail "GH_TOKEN should be unset for the agent (got: $(grep GH_TOKEN "$tmp/research/gh-env.txt" 2>/dev/null))"
grep -q 'GITHUB_TOKEN=\[UNSET\]' "$tmp/research/gh-env.txt" 2>/dev/null \
  && pass "GITHUB_TOKEN stripped from agent env" \
  || fail "GITHUB_TOKEN should be unset for the agent"
rm -rf "$tmp"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
