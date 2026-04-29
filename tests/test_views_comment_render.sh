#!/usr/bin/env bash
# Snapshot test for views-comment.sh: render against fixture .view-candidacy.json,
# diff against the golden file.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing views-comment.sh..."

# Stub gh to capture the body.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; printf '%s' "$1" > "$CAPTURE_FILE"; shift ;;
    *) shift ;;
  esac
done
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# Decompose fixture.
mkdir -p "$TMP/decompose"
cp "$REPO_ROOT/tests/fixtures/view-candidacy/decompose.json" "$TMP/decompose/.view-candidacy.json"
export CAPTURE_FILE="$TMP/decompose-body.md"
ISSUE_NUMBER=42 GH_TOKEN=x GH_REPO=x/y RESEARCH_DIR="$TMP/decompose" \
  bash "$REPO_ROOT/scripts/views-comment.sh"

if diff -u "$REPO_ROOT/tests/fixtures/comments/candidacy-decompose.golden.md" "$CAPTURE_FILE"; then
  pass "decompose render matches golden"
else
  fail "decompose render diverged"
fi

# Single-pass fixture.
mkdir -p "$TMP/single"
cp "$REPO_ROOT/tests/fixtures/view-candidacy/singlepass.json" "$TMP/single/.view-candidacy.json"
export CAPTURE_FILE="$TMP/single-body.md"
ISSUE_NUMBER=43 GH_TOKEN=x GH_REPO=x/y RESEARCH_DIR="$TMP/single" \
  bash "$REPO_ROOT/scripts/views-comment.sh"

if diff -u "$REPO_ROOT/tests/fixtures/comments/candidacy-singlepass.golden.md" "$CAPTURE_FILE"; then
  pass "singlepass render matches golden"
else
  fail "singlepass render diverged"
fi

# Regression: parent hint must appear even if should_offer_view is false.
mkdir -p "$TMP/parent-fallback"
cat > "$TMP/parent-fallback/.view-candidacy.json" <<'EOF'
{
  "items": [
    {"row":"parent","slug":"x","path":"research/x","title":"X","should_offer_view":false,"view_name":"dashboard","title_suffix":"Dashboard","vibe_hint":"foo"}
  ]
}
EOF
export CAPTURE_FILE="$TMP/parent-fallback-body.md"
ISSUE_NUMBER=44 GH_TOKEN=x GH_REPO=x/y RESEARCH_DIR="$TMP/parent-fallback" \
  bash "$REPO_ROOT/scripts/views-comment.sh"
if grep -q '^- \[x\] \*\*X\*\* — register: dashboard' "$CAPTURE_FILE"; then
  pass "parent shows hint regardless of should_offer_view"
else
  fail "parent missed hint when should_offer_view=false"
fi

echo
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
