#!/usr/bin/env bash
# Tests soft + hard timeout in run-decompose.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

setup() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/atlas-checkout"
  cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$tmp/scout/scripts/"
  cp "$REPO_ROOT/scripts/run-decompose.sh"   "$tmp/scout/scripts/"
  echo "$tmp"
}

# --- Soft timeout: stub run.sh sleeps 3s; soft timeout = 2s; second child
#                  is skipped with a placeholder. ---
TMP=$(setup)
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
sleep 3
cat > "$RESEARCH_DIR/index.md" <<MD
---
status: success
---
done
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true\nB|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_DECOMPOSE_SOFT_TIMEOUT=2 \
    SCOUT_DECOMPOSE_HARD_TIMEOUT=10 \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

# A should be successful, B should be a soft-timeout placeholder.
[ -f "$TMP/atlas-checkout/p/a/index.md" ] && \
  grep -q 'status: success' "$TMP/atlas-checkout/p/a/index.md" && \
  pass "soft: A succeeded" || fail "soft: A missing or not success"
[ -f "$TMP/atlas-checkout/p/b/index.md" ] && \
  grep -q 'failure_reason: soft timeout reached before start' "$TMP/atlas-checkout/p/b/index.md" && \
  pass "soft: B placeholder" || fail "soft: B not a soft-timeout placeholder"

# --- Hard timeout: stub sleeps 5s; hard cap forces remaining=1s, kills child. ---
TMP=$(setup)
cat > "$TMP/scout/scripts/run.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "$RESEARCH_DIR"
sleep 5
cat > "$RESEARCH_DIR/index.md" <<MD
---
status: success
---
done
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

env PARENT_DIR="$TMP/atlas-checkout/p" \
    PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard||true' \
    SCOUT_DIR="$TMP/scout" \
    SCOUT_DECOMPOSE_SOFT_TIMEOUT=3600 \
    SCOUT_DECOMPOSE_HARD_TIMEOUT=2 \
    SCOUT_DECOMPOSE_MIN_REMAINING=1 \
    SCOUT_SKIP_SYNTHESIS=1 \
    bash "$TMP/scout/scripts/run-decompose.sh"

[ -f "$TMP/atlas-checkout/p/a/index.md" ] && \
  grep -q 'failure_reason: hard timeout' "$TMP/atlas-checkout/p/a/index.md" && \
  pass "hard: A killed" || fail "hard: A not a hard-timeout placeholder"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
