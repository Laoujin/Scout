#!/usr/bin/env bash
# Regression: a synthesis-phase agent (synthesis / scout-illustrator) runs with
# --dangerously-skip-permissions and has write access to PARENT_DIR. Such agents
# were observed clobbering manifest.json mid-run (head truncated → leading ","),
# which made it unparseable and tripped scan.py's MANIFEST_MISMATCH. The
# orchestrator must re-materialise manifest.json from its in-memory entries just
# before publish, so the committed file is always complete and parseable.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run_decompose_manifest_integrity.sh..."

TMP=$(mktemp -d)
PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test"
mkdir -p "$TMP/scout/scripts" "$TMP/scout/skills/scout" "$PARENT_DIR" "$TMP/bin"

# Stub run.sh — writes a successful child index.md.
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
cat > "$RESEARCH_DIR/index.md" <<MD
---
title: $TOPIC
status: success
citations: 3
reading_time_min: 2
cost_usd: 1.00
duration_sec: 300
summary: Stubbed.
---
stub child body
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

# Stub publish.sh — no-op (we assert on the on-disk manifest, not git).
cat > "$TMP/scout/scripts/publish.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TMP/scout/scripts/publish.sh"

echo "stub synthesis skill" > "$TMP/scout/skills/scout/synthesis.md"

# Stub claude — simulates the synthesis agent: writes the parent index.md AND
# clobbers manifest.json the way the real agents did (head removed, leading ",").
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
# Corrupt the manifest mid-run, exactly the observed failure signature.
if [ -f "\$PD/manifest.json" ]; then
  printf ',\n  {"slug":"c"}\n]\n' > "\$PD/manifest.json"
fi
echo '{"result":"ok","total_cost_usd":0.10,"duration_ms":1000}'
STUB
chmod +x "$TMP/bin/claude"

cp "$REPO_ROOT/scripts/run-decompose.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/lib-models.sh" "$TMP/scout/scripts/"

env PATH="$TMP/bin:$PATH" \
    PARENT_DIR="$PARENT_DIR" \
    PARENT_TOPIC="Parent topic" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|rA|true\nB|standard|rB|true\nC|ceo|rC|true' \
    SCOUT_DIR="$TMP/scout" \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    bash "$TMP/scout/scripts/run-decompose.sh" >"$TMP/run.log" 2>&1
RC=$?

[ "$RC" = "0" ] && pass "run-decompose exits 0" \
                || fail "run-decompose exit=$RC, log: $(cat "$TMP/run.log")"

# The title-based slug rename may have moved the parent dir.
ACTUAL_PARENT="$(find "$TMP/atlas-checkout/research" -maxdepth 1 -name "2026-04-26-*" -type d | head -1)"
[ -n "$ACTUAL_PARENT" ] && PARENT_DIR="$ACTUAL_PARENT"
MANIFEST="$PARENT_DIR/manifest.json"

# Despite the agent corrupting it mid-run, the committed manifest must be valid.
[ "$(head -c1 "$MANIFEST" 2>/dev/null)" = "[" ] \
  && pass "manifest.json starts with '[' (head not truncated)" \
  || fail "manifest.json first byte is '$(head -c1 "$MANIFEST" 2>/dev/null)', expected '['"

jq -e . "$MANIFEST" >/dev/null 2>&1 \
  && pass "manifest.json is parseable JSON" \
  || fail "manifest.json is not valid JSON: $(cat "$MANIFEST" 2>/dev/null)"

COUNT="$(jq 'length' "$MANIFEST" 2>/dev/null)"
[ "$COUNT" = "3" ] \
  && pass "manifest.json lists all 3 children" \
  || fail "manifest.json has $COUNT entries (expected 3)"

SLUGS="$(jq -r '.[].slug' "$MANIFEST" 2>/dev/null | paste -sd, -)"
[ "$SLUGS" = "a,b,c" ] \
  && pass "manifest.json children in loop order (a,b,c)" \
  || fail "manifest slugs '$SLUGS' (expected a,b,c)"

rm -rf "$TMP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
