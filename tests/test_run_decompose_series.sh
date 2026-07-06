#!/usr/bin/env bash
# Verifies run-decompose.sh adds the parent expedition to an existing Atlas
# series (via add-to-series.sh) BEFORE the final publish, so the series.yml
# edit is swept into the publish commit. Mirrors the single-pass wiring in
# run.sh, which the decompose path originally lacked (series v1 was single-pass
# only).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run_decompose_series.sh..."

TMP=$(mktemp -d)
PARENT_DIR="$TMP/atlas-checkout/research/2026-04-26-test"
mkdir -p "$TMP/scout/scripts" "$TMP/scout/skills/scout-research" "$PARENT_DIR" \
         "$TMP/atlas-checkout/_data" "$TMP/bin"

# Real series.yml with an existing series + group; add-to-series.sh only
# inserts into an EXISTING group, never creates one.
cat > "$TMP/atlas-checkout/_data/series.yml" <<'YML'
- slug: michelin-weekends
  title: Michelin weekend getaways
  blurb: test
  groups:
    - label: Testland
      entries:
        - 2026-01-01-existing-entry
YML

# Stub run.sh — writes a successful child index.md.
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

# Stub publish.sh — snapshots series.yml AS SEEN at publish time. This proves
# add-to-series ran BEFORE publish (ordering), not merely at some point.
PUBLISH_LOG="$TMP/publish.log"
cat > "$TMP/scout/scripts/publish.sh" <<STUB
#!/usr/bin/env bash
cp "$TMP/atlas-checkout/_data/series.yml" "$TMP/publish-snapshot.yml"
echo "---invocation---" >> "$PUBLISH_LOG"
STUB
chmod +x "$TMP/scout/scripts/publish.sh"

echo "stub synthesis skill" > "$TMP/scout/skills/scout-research/synthesis.md"

# Stub claude — writes a parent synthesis index.md with a known title (drives
# the slug rename) and emits cost/duration JSON.
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
echo '{"result":"ok","total_cost_usd":0.42,"duration_ms":15000}'
STUB
chmod +x "$TMP/bin/claude"

# Real run-decompose.sh + real add-to-series.sh (integration, not mocks).
cp "$REPO_ROOT/scripts/run-decompose.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/add-to-series.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/lib-models.sh" "$TMP/scout/scripts/"

env PATH="$TMP/bin:$PATH" \
    PARENT_DIR="$PARENT_DIR" \
    PARENT_TOPIC="Parent topic" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true' \
    SCOUT_DIR="$TMP/scout" \
    ATLAS_REPO="git@github.com-atlas:test/atlas.git" \
    SERIES_SLUG="michelin-weekends" \
    SERIES_GROUP="Testland" \
    ISSUE_NUMBER="42" \
    GH_TOKEN="x" \
    GH_REPO="test/scout" \
    bash "$TMP/scout/scripts/run-decompose.sh" >"$TMP/run.log" 2>&1
RC=$?

[ "$RC" = "0" ] && pass "run-decompose exits 0" \
                || fail "run-decompose exit=$RC, log: $(cat "$TMP/run.log")"

# The title-based slug rename moved the parent dir; find the real slug.
ACTUAL_PARENT="$(find "$TMP/atlas-checkout/research" -maxdepth 1 -name "2026-04-26-*" -type d | head -1)"
ACTUAL_SLUG="$(basename "$ACTUAL_PARENT")"

[ -f "$TMP/publish-snapshot.yml" ] || fail "publish was never invoked (no snapshot)"

# The parent entry is present in series.yml at publish time, under the group.
if grep -qE "^[[:space:]]*-[[:space:]]+${ACTUAL_SLUG}[[:space:]]*$" "$TMP/publish-snapshot.yml" 2>/dev/null; then
  pass "parent entry ($ACTUAL_SLUG) inserted into series.yml before publish"
else
  fail "parent entry ($ACTUAL_SLUG) NOT in series.yml at publish time; snapshot: $(cat "$TMP/publish-snapshot.yml" 2>/dev/null)"
fi

# It landed inside the Testland group (after the existing entry), not elsewhere.
if [ -f "$TMP/publish-snapshot.yml" ]; then
  group_block="$(awk '/- label: Testland/{f=1} f&&/- label:/&&!/Testland/{exit} f' "$TMP/publish-snapshot.yml")"
  printf '%s\n' "$group_block" | grep -qE "^[[:space:]]*-[[:space:]]+${ACTUAL_SLUG}[[:space:]]*$" \
    && pass "parent entry filed under the Testland group" \
    || fail "parent entry not under Testland group; block: $group_block"
fi

rm -rf "$TMP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
