#!/usr/bin/env bash
# Verifies run-decompose.sh invokes publish.sh exactly once after all children
# finish, with parent-level env vars (one commit covers parent + every child),
# and that children land as subfolders of the parent — not as top-level
# siblings on Atlas's homepage.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run_decompose_publish.sh..."

TMP=$(mktemp -d)
PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test"
mkdir -p "$TMP/scout/scripts" "$TMP/scout/skills/scout" "$PARENT_DIR" "$TMP/bin"

# Stub run.sh — writes a successful child index.md at $RESEARCH_DIR with all
# four metric fields (cost_usd, duration_sec, citations, reading_time_min)
# so the parent's aggregation has something to sum.
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: $TOPIC
status: success
citations: 5
reading_time_min: 2
cost_usd: 1.50
duration_sec: 600
summary: Stubbed.
---
stub child body
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

# Stub publish.sh — records every invocation's env.
PUBLISH_LOG="$TMP/publish.log"
cat > "$TMP/scout/scripts/publish.sh" <<STUB
#!/usr/bin/env bash
{
  echo "---invocation---"
  echo "TOPIC=\$TOPIC"
  echo "SLUG=\$SLUG"
  echo "DATE=\$DATE"
  echo "RESEARCH_DIR=\$RESEARCH_DIR"
  echo "ISSUE_NUMBER=\$ISSUE_NUMBER"
  echo "GH_REPO=\$GH_REPO"
  echo "PWD=\$(pwd)"
} >> "$PUBLISH_LOG"
STUB
chmod +x "$TMP/scout/scripts/publish.sh"

# Stub synthesis skill (run-decompose only reads its content).
echo "stub synthesis skill" > "$TMP/scout/skills/scout/synthesis.md"

# Stub claude on PATH — writes a parent index.md so the synthesis fallback
# path isn't exercised here.
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
PD="$PARENT_DIR"
cat > "\$PD/index.md" <<EOF
---
layout: expedition
title: Test parent
synthesis: true
---
synthesis prose
EOF
# Emit cost + duration so the orchestrator has parent synthesis numbers to add.
echo '{"result":"ok","total_cost_usd":0.42,"duration_ms":15000}'
STUB
chmod +x "$TMP/bin/claude"

cp "$REPO_ROOT/scripts/run-decompose.sh" "$TMP/scout/scripts/"

env PATH="$TMP/bin:$PATH" \
    PARENT_DIR="$PARENT_DIR" \
    PARENT_TOPIC="Parent topic" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true' \
    SCOUT_DIR="$TMP/scout" \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    ISSUE_NUMBER="42" \
    GH_TOKEN="x" \
    GH_REPO="test/scout" \
    bash "$TMP/scout/scripts/run-decompose.sh" >"$TMP/run.log" 2>&1
RC=$?

[ "$RC" = "0" ] && pass "run-decompose exits 0" \
                || fail "run-decompose exit=$RC, log: $(cat "$TMP/run.log")"

# The title-based slug rename may have moved the parent dir.
# Find the actual location for subsequent assertions.
ACTUAL_PARENT="$(find "$TMP/atlas-checkout/research" -maxdepth 1 -name "2026-04-26-*" -type d | head -1)"
[ -n "$ACTUAL_PARENT" ] && PARENT_DIR="$ACTUAL_PARENT"
ACTUAL_SLUG="$(basename "$PARENT_DIR")"; ACTUAL_SLUG="${ACTUAL_SLUG#2026-04-26-}"

# publish.sh invoked exactly once
count=$(grep -c '^---invocation---' "$PUBLISH_LOG" 2>/dev/null || true)
[ "$count" = "1" ] && pass "publish.sh invoked exactly once" \
                   || fail "publish.sh invocations=$count (expected 1)"

# Parent-level env vars passed to publish.sh
grep -qF "TOPIC=Parent topic" "$PUBLISH_LOG" \
  && pass "publish.sh got PARENT_TOPIC" \
  || fail "publish.sh wrong TOPIC: $(grep TOPIC "$PUBLISH_LOG")"

grep -qF "SLUG=$ACTUAL_SLUG" "$PUBLISH_LOG" \
  && pass "publish.sh got parent SLUG (date prefix stripped)" \
  || fail "publish.sh wrong SLUG: $(grep SLUG "$PUBLISH_LOG")"

grep -qF "RESEARCH_DIR=$PARENT_DIR" "$PUBLISH_LOG" \
  && pass "publish.sh RESEARCH_DIR points at parent expedition" \
  || fail "publish.sh wrong RESEARCH_DIR: $(grep RESEARCH_DIR "$PUBLISH_LOG")"

grep -qF "ISSUE_NUMBER=42" "$PUBLISH_LOG" \
  && pass "publish.sh got ISSUE_NUMBER" \
  || fail "publish.sh missing ISSUE_NUMBER"

# Children landed as subfolders of the parent — not as top-level siblings.
[ -f "$PARENT_DIR/a/index.md" ] && pass "child A nested under parent" \
                                || fail "child A missing at $PARENT_DIR/a/index.md"
[ -f "$PARENT_DIR/b/index.md" ] && pass "child B nested under parent" \
                                || fail "child B missing at $PARENT_DIR/b/index.md"

# No flat top-level leakage (the prior bug — children appearing as their own
# Atlas cards).
[ ! -d "$TMP/atlas-checkout/research/2026-04-26-a" ] \
  && pass "child A NOT leaked as top-level Atlas folder" \
  || fail "child A leaked to top-level"
[ ! -d "$TMP/atlas-checkout/research/2026-04-26-b" ] \
  && pass "child B NOT leaked as top-level Atlas folder" \
  || fail "child B leaked to top-level"

# Parent index.md exists (synthesis output)
[ -f "$PARENT_DIR/index.md" ] && pass "parent expedition index.md present" \
                              || fail "parent index.md missing"

# Aggregated metrics: synthesis (0.42, 15s) + 2 children (1.50, 600s, cites=5, read=2 each)
grep -q '^cost_usd: 3\.42$' "$PARENT_DIR/index.md" \
  && pass "parent cost_usd = synthesis + sum(children)" \
  || fail "wrong cost_usd: $(grep ^cost_usd "$PARENT_DIR/index.md")"

grep -q '^duration_sec: 1215$' "$PARENT_DIR/index.md" \
  && pass "parent duration_sec = synthesis + sum(children)" \
  || fail "wrong duration_sec: $(grep ^duration_sec "$PARENT_DIR/index.md")"

grep -q '^citations: 10$' "$PARENT_DIR/index.md" \
  && pass "parent citations = sum(children)" \
  || fail "wrong citations: $(grep ^citations "$PARENT_DIR/index.md")"

grep -q '^reading_time_min: 4$' "$PARENT_DIR/index.md" \
  && pass "parent reading_time_min = sum(children)" \
  || fail "wrong reading_time_min: $(grep ^reading_time "$PARENT_DIR/index.md")"

rm -rf "$TMP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
