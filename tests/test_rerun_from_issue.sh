#!/usr/bin/env bash
# Integration test for rerun-from-issue.sh: from a rerun comment it locates the
# expedition in a (stub-cloned) Atlas, reconstructs sub-topics from the
# manifest, and execs run-decompose with the right env.

set -u
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing rerun-from-issue.sh..."

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Isolated scout dir with the real handler + lib and a stubbed run-decompose.
mkdir -p "$TMP/scout/scripts" "$TMP/bin"
cp "$REPO_ROOT/scripts/rerun-from-issue.sh" "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/lib-rerun-parse.sh"  "$TMP/scout/scripts/"
cat > "$TMP/scout/scripts/run-decompose.sh" <<'STUB'
#!/usr/bin/env bash
{
  echo "PARENT_DIR=$PARENT_DIR"
  echo "PARENT_TOPIC=$PARENT_TOPIC"
  echo "DATE=$DATE"
  echo "ISSUE_NUMBER=$ISSUE_NUMBER"
  echo "---TSV---"
  printf '%s\n' "$SUB_TOPICS_TSV"
} > "$DECOMPOSE_CAPTURE"
STUB
chmod +x "$TMP/scout/scripts/run-decompose.sh"

# Source Atlas the stub `git clone` will copy into place.
SRC_ATLAS="$TMP/src-atlas"
EXP="$SRC_ATLAS/research/2026-05-25-a-heist-weekend"
mkdir -p "$EXP"
cat > "$EXP/manifest.json" <<'JSON'
[
  {"slug":"lodging","title":"Walking-distance lodging","depth":"standard","status":"success","start":1,"end":2},
  {"slug":"activities","title":"Day-trips and activities","depth":"deep","status":"failed","start":1,"end":2}
]
JSON
cat > "$EXP/index.md" <<'MD'
---
layout: expedition
title: A Heist weekend
topic: "Plan a weekend in **Heist**: dinner at Bartholomeus"
date: 2026-05-25
---
body
MD

# Stub git: `git clone ... <repo> <dir>` copies the source atlas to <dir>.
cat > "$TMP/bin/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "clone" ]; then
  dst="${@: -1}"; src="${@: -2:1}"
  cp -r "$src" "$dst"
fi
STUB
chmod +x "$TMP/bin/git"

BODY="$(cat <<'EOF'
### Some sub-topics failed
- `activities` — hard timeout
- [x] **Re-run failed sub-topics**
<!-- scout-rerun: 2026-05-25-a-heist-weekend -->
EOF
)"

export DECOMPOSE_CAPTURE="$TMP/capture.txt"
PATH="$TMP/bin:$PATH" \
  env BOT_COMMENT_BODY="$BODY" ISSUE_NUMBER=61 GH_TOKEN=x GH_REPO=o/r \
      ATLAS_REPO="$SRC_ATLAS" \
      bash "$TMP/scout/scripts/rerun-from-issue.sh" >/dev/null 2>&1
rc=$?

[ "$rc" -eq 0 ] && pass "handler exits 0" || fail "handler failed (rc=$rc)"
if [ -f "$DECOMPOSE_CAPTURE" ]; then
  cap="$(cat "$DECOMPOSE_CAPTURE")"
  grep -q 'DATE=2026-05-25' "$DECOMPOSE_CAPTURE" && pass "DATE parsed from folder" || fail "wrong DATE"
  grep -q 'research/2026-05-25-a-heist-weekend$' "$DECOMPOSE_CAPTURE" && pass "PARENT_DIR points at the expedition" || fail "wrong PARENT_DIR"
  grep -q 'PARENT_TOPIC=Plan a weekend in \*\*Heist\*\*: dinner at Bartholomeus' "$DECOMPOSE_CAPTURE" \
    && pass "PARENT_TOPIC unquoted from frontmatter" || fail "wrong PARENT_TOPIC: $(grep PARENT_TOPIC= "$DECOMPOSE_CAPTURE")"
  grep -q 'Walking-distance lodging|standard||true' "$DECOMPOSE_CAPTURE" \
    && grep -q 'Day-trips and activities|deep||true' "$DECOMPOSE_CAPTURE" \
    && pass "all sub-topics reconstructed as checked" || fail "TSV reconstruction wrong"
else
  fail "run-decompose was not invoked"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
