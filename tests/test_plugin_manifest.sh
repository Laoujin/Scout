#!/usr/bin/env bash
# Asserts the Claude Code plugin + marketplace manifests are well-formed, and that
# exactly two skills (scout, scout-async) are user-invocable as bare /scout and
# /scout-async while every other skill is inert (a bundled file read by path).
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

# --- plugin.json: name, and it registers NEITHER commands NOR agents ---
# commands are skills now; agents are deliberately unregistered so they can't
# auto-delegate in a user's session — they stay in .claude/agents/ for the CI runner.
[ "$(jq -r '.name' "$PLG")" = "scout" ] && pass "plugin.json name = scout" || fail "plugin.json name not scout"
jq -e 'has("commands")' "$PLG" >/dev/null 2>&1 \
  && fail "plugin.json should not declare 'commands' (commands are skills)" \
  || pass "plugin.json has no 'commands' field"
jq -e 'has("agents")' "$PLG" >/dev/null 2>&1 \
  && fail "plugin.json should not register agents (would make them auto-delegatable)" \
  || pass "plugin.json does not register agents"

# --- agents live in .claude/agents/ (CI-only) and carry the internal-only guard ---
for a in scout-illustrator scout-researcher scout-reviewer; do
  f="$REPO_ROOT/.claude/agents/$a.md"
  [ -f "$f" ] && pass "agent $a present in .claude/agents (for CI)" || fail "agent $a missing from .claude/agents"
  grep -qi 'INTERNAL Scout sub-agent' "$f" && pass "agent $a guarded against auto-select" || fail "agent $a missing internal-only guard"
done

# --- the two invocable entry skills: name → bare /scout & /scout-async, user-invocable ---
for s in scout scout-async; do
  f="$REPO_ROOT/skills/$s/SKILL.md"
  [ -f "$f" ] && pass "skill $s present" || { fail "skill $s missing"; continue; }
  grep -qx "name: $s" "$f" && pass "skill $s has name: $s (→ /$s)" || fail "skill $s missing 'name: $s'"
  grep -q 'user-invocable: false' "$f" && fail "skill $s must stay user-invocable" || pass "skill $s is user-invocable"
done
grep -RIl '{{SCOUT_REPO}}\|{{ATLAS_URL}}' "$REPO_ROOT/skills/scout" "$REPO_ROOT/skills/scout-async" >/dev/null 2>&1 \
  && fail "install-time placeholders still in entry skills" \
  || pass "no {{...}} install-time placeholders in entry skills"

# --- every OTHER skill is inert (not user-invocable, not model-invoked) ---
for s in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$s")")"
  case "$name" in scout|scout-async) continue ;; esac
  grep -qx 'user-invocable: false' "$s" && pass "skill $name: user-invocable: false" \
    || fail "skill $name missing 'user-invocable: false'"
  grep -qx 'disable-model-invocation: true' "$s" && pass "skill $name: disable-model-invocation: true" \
    || fail "skill $name missing 'disable-model-invocation: true'"
done

# --- the internal research playbook is scout-research, not colliding with the scout skill ---
[ -f "$REPO_ROOT/skills/scout-research/SKILL.md" ] && pass "skills/scout-research exists" || fail "skills/scout-research missing"
grep -qx 'name: scout-research' "$REPO_ROOT/skills/scout-research/SKILL.md" \
  && pass "playbook named scout-research (distinct from the scout skill)" \
  || fail "skills/scout-research not named scout-research"

# --- no stale references to the pre-rename playbook sub-files under skills/scout/ ---
if grep -rn 'skills/scout/\(sharpen\|deep\|synthesis\|view-candidacy\)\.md' \
     "$REPO_ROOT/scripts" "$REPO_ROOT/skills" 2>/dev/null | grep -q .; then
  fail "a file still references a pre-rename playbook path under skills/scout/"
else
  pass "no stale skills/scout/ playbook refs"
fi

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
