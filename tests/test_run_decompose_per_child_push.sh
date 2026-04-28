#!/usr/bin/env bash
# Verifies run-decompose.sh pushes each successful child to the Atlas remote
# BEFORE running the next child, so a mid-expedition crash doesn't lose the
# work of children that already finished.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing run_decompose_per_child_push.sh..."

TMP=$(mktemp -d)
ATLAS_REMOTE="$TMP/atlas-remote.git"
ATLAS_DIR="$TMP/scout/atlas-checkout"
PARENT_DIR="$ATLAS_DIR/research/2026-04-26-test"

mkdir -p "$TMP/scout/scripts" "$TMP/scout/skills/scout" "$TMP/bin"

# --- Fake Atlas remote -------------------------------------------------------
git -c init.defaultBranch=main init -q "$TMP/seed"
git -C "$TMP/seed" -c user.name=seed -c user.email=s@s commit --allow-empty -q -m "init"
git clone -q --bare "$TMP/seed" "$ATLAS_REMOTE"
rm -rf "$TMP/seed"
git clone -q "$ATLAS_REMOTE" "$ATLAS_DIR"

# --- Stub run.sh: snapshots remote state, then writes a successful child ---
cat > "$TMP/scout/scripts/run.sh" <<STUB
#!/usr/bin/env bash
mkdir -p "\$RESEARCH_DIR"
# Snapshot what's on remote main right now, indexed by topic.
git --git-dir="$ATLAS_REMOTE" log main --format=%s > "$TMP/remote-at-\$TOPIC.txt"
cat > "\$RESEARCH_DIR/index.md" <<MD
---
title: \$TOPIC
status: success
citations: 5
reading_time_min: 2
cost_usd: 1.50
duration_sec: 600
summary: stub
---
stub child body for \$TOPIC
MD
STUB
chmod +x "$TMP/scout/scripts/run.sh"

# --- Real lib-publish.sh + run-decompose.sh + slug.sh + lib-issue-parse.sh ---
cp "$REPO_ROOT/scripts/lib-publish.sh"      "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/lib-issue-parse.sh"  "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/slug.sh"             "$TMP/scout/scripts/"
cp "$REPO_ROOT/scripts/run-decompose.sh"    "$TMP/scout/scripts/"
# Real publish.sh handles the final parent commit.
cp "$REPO_ROOT/scripts/publish.sh"          "$TMP/scout/scripts/"
echo "stub synthesis skill" > "$TMP/scout/skills/scout/synthesis.md"

# --- Stub claude (synthesis pass) ---
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

# --- Run the orchestrator ---
env PATH="$TMP/bin:$PATH" \
    PARENT_DIR="$PARENT_DIR" \
    PARENT_TOPIC="Parent topic" \
    PARENT_FORMAT="md" \
    DATE=2026-04-26 \
    SUB_TOPICS_TSV=$'A|standard|reasonA|true\nB|standard|reasonB|true' \
    SCOUT_DIR="$TMP/scout" \
    ATLAS_REPO="$ATLAS_REMOTE" \
    GH_TOKEN="" GH_REPO="" ISSUE_NUMBER="" \
    GIT_AUTHOR_NAME="tester" GIT_AUTHOR_EMAIL="t@t" \
    bash "$TMP/scout/scripts/run-decompose.sh" >"$TMP/run.log" 2>&1
RC=$?

[ "$RC" = "0" ] && pass "run-decompose exits 0" \
                || fail "run-decompose exit=$RC, log:\n$(cat "$TMP/run.log")"

# The title-based slug rename may have moved the parent dir.
ACTUAL_PARENT="$(find "$ATLAS_DIR/research" -maxdepth 1 -name "2026-04-26-*" -type d | head -1)"
[ -n "$ACTUAL_PARENT" ] && PARENT_DIR="$ACTUAL_PARENT"
ACTUAL_SLUG="$(basename "$PARENT_DIR")"; ACTUAL_SLUG="${ACTUAL_SLUG#2026-04-26-}"

# --- Per-child push happens BEFORE next child runs ---
# When A's stub ran, remote had only the init commit.
[ -f "$TMP/remote-at-A.txt" ] \
  && [ "$(grep -c . "$TMP/remote-at-A.txt")" = "1" ] \
  && grep -q '^init$' "$TMP/remote-at-A.txt" \
  && pass "child A: remote had only init at start" \
  || fail "child A: remote state at start unexpected:\n$(cat "$TMP/remote-at-A.txt" 2>/dev/null)"

# When B's stub ran, remote ALREADY had A's commit pushed.
[ -f "$TMP/remote-at-B.txt" ] \
  && grep -q 'research: 2026-04-26 test/a' "$TMP/remote-at-B.txt" \
  && pass "child B: remote already had child A's commit before B started" \
  || fail "child B: remote did not have child A's commit yet:\n$(cat "$TMP/remote-at-B.txt" 2>/dev/null)"

# --- Final remote state: 3 research commits + init = 4, in correct order ---
mapfile -t MAIN_LOG < <(git --git-dir="$ATLAS_REMOTE" log main --format=%s)
[ "${#MAIN_LOG[@]}" -eq 4 ] \
  && pass "remote main has 4 commits (init + 2 children + parent)" \
  || fail "remote main commit count: ${#MAIN_LOG[@]} — log:\n$(printf '%s\n' "${MAIN_LOG[@]}")"

# Top of log = parent synthesis commit (may use renamed slug)
[ "${MAIN_LOG[0]}" = "research: 2026-04-26 $ACTUAL_SLUG" ] \
  && pass "top commit is parent synthesis" \
  || fail "top commit was '${MAIN_LOG[0]}'"

# Children land as separate commits with parent-slug/child-slug subject
git --git-dir="$ATLAS_REMOTE" log main --format=%s | grep -qx 'research: 2026-04-26 test/a' \
  && pass "child A has its own commit on remote" \
  || fail "child A commit not found in:\n$(printf '%s\n' "${MAIN_LOG[@]}")"
git --git-dir="$ATLAS_REMOTE" log main --format=%s | grep -qx 'research: 2026-04-26 test/b' \
  && pass "child B has its own commit on remote" \
  || fail "child B commit not found in:\n$(printf '%s\n' "${MAIN_LOG[@]}")"

# --- All three artifacts present on remote main (under renamed path) ---
git --git-dir="$ATLAS_REMOTE" show "main:research/2026-04-26-$ACTUAL_SLUG/a/index.md" >/dev/null 2>&1 \
  && pass "child A index.md is on remote main" || fail "child A index.md missing on remote"
git --git-dir="$ATLAS_REMOTE" show "main:research/2026-04-26-$ACTUAL_SLUG/b/index.md" >/dev/null 2>&1 \
  && pass "child B index.md is on remote main" || fail "child B index.md missing on remote"
git --git-dir="$ATLAS_REMOTE" show "main:research/2026-04-26-$ACTUAL_SLUG/index.md" >/dev/null 2>&1 \
  && pass "parent index.md is on remote main" || fail "parent index.md missing on remote"

rm -rf "$TMP"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
