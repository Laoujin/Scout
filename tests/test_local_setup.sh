#!/usr/bin/env bash
# Tests scripts/local-setup.sh: resolves SCOUT_DIR/ATLAS_REPO, clones, makes
# dirs, prints env. Hermetic: SCOUT_DIR is a throwaway under $WORK (native /tmp),
# pointed to via a fake $HOME/.scout/dir — so the script never clones into the
# real repo (no pollution, and no Windows-mount .git lock from /mnt/c).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Throwaway SCOUT_DIR with the only things local-setup.sh reads from it.
SCOUTD="$WORK/scout"
mkdir -p "$SCOUTD/skills/scout" "$SCOUTD/scripts"
touch "$SCOUTD/skills/scout/SKILL.md"
cp "$REPO_ROOT/scripts/slug.sh" "$SCOUTD/scripts/slug.sh"
# Fake HOME so the script resolves SCOUT_DIR from ~/.scout/dir.
FAKE_HOME="$WORK/home"; mkdir -p "$FAKE_HOME/.scout"
printf '%s\n' "$SCOUTD" > "$FAKE_HOME/.scout/dir"

# Fake Atlas remote.
FAKE_ATLAS="$WORK/atlas.git"
mkdir -p "$FAKE_ATLAS" && ( cd "$FAKE_ATLAS" && git init -q && mkdir -p research \
  && echo "seed" > research/.keep && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm seed )

run() { HOME="$FAKE_HOME" DATE=2026-06-02 ATLAS_REPO="$FAKE_ATLAS" SUB_TOPICS_TSV="$1" \
        bash "$REPO_ROOT/scripts/local-setup.sh" "$2"; }

# --- expedition: two sub-topics ---
OUT="$(run $'Routing angle\tdeep\nState angle\tsurvey' 'My Expedition Topic')"
echo "$OUT" | grep -q "^SCOUT_DIR=$SCOUTD$" && pass "prints SCOUT_DIR" || fail "no/!= SCOUT_DIR"
echo "$OUT" | grep -q '^DATE=2026-06-02$' && pass "prints DATE" || fail "no DATE"
echo "$OUT" | grep -q '^START_TS=[0-9]\+$' && pass "prints START_TS" || fail "no START_TS"
PARENT="$(echo "$OUT" | sed -n 's/^PARENT_DIR=//p')"
case "$PARENT" in */research/2026-06-02-my-expedition-topic) pass "parent dir slug" ;; *) fail "bad parent: $PARENT" ;; esac
[ -d "$PARENT" ] && pass "parent dir created" || fail "parent not created"
[ "$(echo "$OUT" | grep -c '^CHILD=')" -eq 2 ] && pass "two CHILD lines" || fail "expected 2 CHILD lines"
[ -d "$PARENT/routing-angle" ] && pass "child dir 1 created" || fail "missing child 1"

# --- uniqueness: a colliding dir already published in Atlas → -2 ---
# Seed the *remote* so the fresh clone contains the collision (production
# uniqueness is checked against the freshly-cloned Atlas, not local state).
( cd "$FAKE_ATLAS" && mkdir -p "research/2026-06-02-my-expedition-topic" \
  && echo x > "research/2026-06-02-my-expedition-topic/index.md" && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm collide )
OUT2="$(run '' 'My Expedition Topic')"
echo "$OUT2" | sed -n 's/^PARENT_DIR=//p' | grep -q -- '-my-expedition-topic-2$' && pass "unique slug -2" || fail "slug not uniquified"

# --- missing ATLAS_REPO → error ---
if HOME="$FAKE_HOME" DATE=2026-06-02 env -u ATLAS_REPO bash "$REPO_ROOT/scripts/local-setup.sh" "X" >/dev/null 2>"$WORK/err"; then
  fail "should error without ATLAS_REPO"
else
  grep -qi 'ATLAS_REPO' "$WORK/err" && pass "clear ATLAS_REPO error" || fail "unclear error"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
