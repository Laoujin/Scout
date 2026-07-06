#!/usr/bin/env bash
# Asserts the Claude Code plugin + marketplace manifests are well-formed and that
# ONLY /scout:scout and /scout:scout-async are user-invocable — every skill is inert
# (a bundled file read by path), so nothing else clutters the slash menu.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

MKT="$REPO_ROOT/.claude-plugin/marketplace.json"
PLG="$REPO_ROOT/.claude-plugin/plugin.json"

# --- manifests exist + valid JSON ---
[ -f "$MKT" ] && pass "marketplace.json exists" || fail "missing $MKT"
[ -f "$PLG" ] && pass "plugin.json exists" || fail "missing $PLG"
jq -e . "$MKT" >/dev/null 2>&1 && pass "marketplace.json is valid JSON" || fail "marketplace.json invalid JSON"
jq -e . "$PLG" >/dev/null 2>&1 && pass "plugin.json is valid JSON" || fail "plugin.json invalid JSON"

# --- marketplace shape ---
[ "$(jq -r '.name' "$MKT")" = "scout" ] && pass "marketplace name = scout" || fail "marketplace name not scout"
[ -n "$(jq -r '.owner.name // empty' "$MKT")" ] && pass "marketplace owner.name set" || fail "marketplace owner.name missing"
[ "$(jq -r '.plugins[0].name' "$MKT")" = "scout" ] && pass "plugin entry name = scout" || fail "plugin entry name not scout"
SRC="$(jq -r '.plugins[0].source' "$MKT")"
[ -d "$REPO_ROOT/$SRC" ] && pass "plugin source path exists ($SRC)" || fail "plugin source path missing: $SRC"

# --- plugin.json shape + referenced component dirs exist ---
[ "$(jq -r '.name' "$PLG")" = "scout" ] && pass "plugin.json name = scout" || fail "plugin.json name not scout"
CMD_DIR="$(jq -r '.commands' "$PLG")"
[ -d "$REPO_ROOT/$CMD_DIR" ] && pass "commands dir exists ($CMD_DIR)" || fail "commands dir missing: $CMD_DIR"
while IFS= read -r a; do
  [ -f "$REPO_ROOT/$a" ] && pass "agent file exists ($a)" || fail "agent file missing: $a"
done < <(jq -r '.agents[]' "$PLG")

# --- the two user-invocable commands are present, and no placeholders survive ---
for c in scout scout-async; do
  f="$REPO_ROOT/$CMD_DIR/$c.md"
  [ -f "$f" ] && pass "command $c.md present" || fail "command $c.md missing"
done
grep -RIl '{{SCOUT_REPO}}\|{{ATLAS_URL}}' "$REPO_ROOT/$CMD_DIR" >/dev/null 2>&1 \
  && fail "install-time placeholders still in command files" \
  || pass "no {{...}} install-time placeholders in commands"

# --- every skill is inert (not user-invocable, not model-invoked) ---
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$s")")"
  grep -qx 'user-invocable: false' "$s" && pass "skill $name: user-invocable: false" \
    || fail "skill $name missing 'user-invocable: false'"
  grep -qx 'disable-model-invocation: true' "$s" && pass "skill $name: disable-model-invocation: true" \
    || fail "skill $name missing 'disable-model-invocation: true'"
done

# --- collider rename is complete ---
[ -f "$REPO_ROOT/skills/scout-research/SKILL.md" ] && pass "skills/scout-research exists" || fail "skills/scout-research missing"
[ ! -d "$REPO_ROOT/skills/scout" ] && pass "old skills/scout removed" || fail "old skills/scout still present"
grep -qx 'name: scout-research' "$REPO_ROOT/skills/scout-research/SKILL.md" \
  && pass "playbook renamed to scout-research (no /scout:scout skill collision)" \
  || fail "skills/scout-research still named 'scout' (would collide with the scout command)"

# --- no functional file still points at the old skills/scout/ path ---
if grep -rn 'skills/scout[/"]' "$REPO_ROOT/scripts" "$REPO_ROOT/.claude" "$REPO_ROOT/skills" 2>/dev/null \
     | grep -vE 'skills/scout-(research|triage|create-series|view-author)' | grep -q .; then
  fail "a functional file still references old skills/scout/ path"
else
  pass "no functional refs to old skills/scout/ path"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
