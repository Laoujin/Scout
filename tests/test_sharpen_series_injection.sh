#!/usr/bin/env bash
# Verify sharpen.sh injects Existing series: and Previous series: blocks.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing sharpen.sh series injection..."

STUB_DIR="$(mktemp -d)"; trap 'rm -rf "$STUB_DIR"' EXIT
cat > "$STUB_DIR/claude" <<'EOF'
#!/usr/bin/env bash
last="${!#}"; printf '%s' "$last"
EOF
chmod +x "$STUB_DIR/claude"

run() { PATH="$STUB_DIR:$PATH" RAW_TOPIC="best ramen" DEPTH=standard \
        SCOUT_PROFILE_FILE=/nonexistent "$@" bash "$REPO_ROOT/scripts/sharpen.sh"; }

# --- manifest present -> Existing series: block injected ---
out=$(SERIES_MANIFEST=$'- slug: michelin-weekends\n  title: Michelin weekends' run) || true
echo "$out" | grep -q "Existing series:" && pass "manifest: block present" || fail "manifest: block missing"
echo "$out" | grep -q "michelin-weekends" && pass "manifest: content passed" || fail "manifest: content missing"

# --- manifest empty/unset -> no Existing series: block ---
out=$(run) || true
echo "$out" | grep -q "Existing series:" && fail "no manifest: unexpected block" || pass "no manifest: no block"

# --- set-but-empty SERIES_MANIFEST -> no Existing series: block ---
out=$(SERIES_MANIFEST="" run) || true
echo "$out" | grep -q "Existing series:" && fail "empty manifest: unexpected block" || pass "empty manifest: no block"

# --- previous series preserved on re-sharpen ---
out=$(PREVIOUS_SERIES=$'- [x] **michelin-weekends** \xe2\x80\xba Germany \xe2\x80\x94 Munich.' run) || true
echo "$out" | grep -q "Previous series:" && pass "resharpen: previous block present" || fail "resharpen: previous block missing"
echo "$out" | grep -q "michelin-weekends" && pass "resharpen: content passed" || fail "resharpen: content missing"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
