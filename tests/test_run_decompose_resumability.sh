#!/usr/bin/env bash
# Verifies run-decompose.sh skips children with an existing non-placeholder
# index.{md,html} and re-runs failure placeholders + missing children.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/run-decompose.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run_decompose_resumability.sh..."

setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/atlas-checkout/research"
  # stub run.sh: marks the RESEARCH_DIR with a sentinel file and writes
  # a minimal successful index.md.
  cat > "$tmp/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
echo "stub run.sh invoked: TOPIC=$TOPIC DEPTH=$DEPTH" >> "$RUN_LOG"
mkdir -p "$RESEARCH_DIR"
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: $TOPIC
status: success
citations: 5
reading_time_min: 2
---
stub body
MD
STUB
  chmod +x "$tmp/scout/scripts/run.sh"
  # Stub claude (used by synthesis pass; we won't reach it in resumability test
  # because we'll force <2 successes after the loop or pre-create successes.)
  cat > "$tmp/scout/scripts/claude-stub.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$tmp/scout/scripts/claude-stub.sh"
  echo "$tmp"
}

# --- Case A: fresh run, all 3 children invoked ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true\nC|standard|reasonC|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 3 ] && pass "fresh run: all 3 children invoked" \
                   || fail "fresh run: expected 3 invocations, got $count"

# --- Case B: pre-existing success at child A — only B and C re-run ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"
mkdir -p "$TMP/atlas-checkout/research/2026-04-26-test/a"
cat > "$TMP/atlas-checkout/research/2026-04-26-test/a/index.md" <<MD
---
title: A
status: success
---
already done
MD

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true\nC|standard|reasonC|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 2 ] && pass "resume: skips A, runs B+C" \
                   || fail "resume: expected 2 invocations, got $count"

# --- Case C: pre-existing failed placeholder at A — A IS re-run ---
TMP=$(setup); RUN_LOG="$TMP/runlog"; touch "$RUN_LOG"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"   "$TMP/scout/scripts/"
mkdir -p "$TMP/atlas-checkout/research/2026-04-26-test/a"
cat > "$TMP/atlas-checkout/research/2026-04-26-test/a/index.md" <<MD
---
title: A
status: failed
failure_reason: timeout
---
placeholder
MD

env PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test" \
    PARENT_TOPIC="Test parent" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true' \
    SCOUT_DIR="$TMP/scout" \
    RUN_LOG="$RUN_LOG" \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

count=$(grep -c "stub run.sh invoked" "$RUN_LOG")
[ "$count" -eq 2 ] && pass "resume-failed: re-runs failed A + B" \
                   || fail "resume-failed: expected 2 invocations, got $count"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
