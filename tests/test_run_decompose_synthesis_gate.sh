#!/usr/bin/env bash
# Verifies synthesis pass invocation:
#   0 successes → no synthesis call
#   1 success   → no synthesis call
#   2+ successes → exactly one synthesis call

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

setup_with_n_successes() {
  local n="$1"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scout/scripts" "$tmp/scout/skills/scout" "$tmp/atlas-checkout"
  cp "$REPO_ROOT/scripts/lib-issue-parse.sh" "$tmp/scout/scripts/"
  cp "$REPO_ROOT/scripts/run-decompose.sh"   "$tmp/scout/scripts/"
  cp "$REPO_ROOT/skills/scout/synthesis.md"  "$tmp/scout/skills/scout/"

  # run.sh stub: writes success for first $n calls, then failure.
  cat > "$tmp/scout/scripts/run.sh" <<STUB
#!/usr/bin/env bash
COUNTER_FILE="\$SCOUT_DIR/scripts/.counter"
[ -f "\$COUNTER_FILE" ] || echo 0 > "\$COUNTER_FILE"
i=\$(cat "\$COUNTER_FILE")
i=\$((i+1)); echo \$i > "\$COUNTER_FILE"
mkdir -p "\$RESEARCH_DIR"
if [ "\$i" -le "$n" ]; then
  cat > "\$RESEARCH_DIR/index.md" <<MD
---
title: stub
status: success
citations: 5
reading_time_min: 2
---
ok
MD
else
  exit 1
fi
STUB
  chmod +x "$tmp/scout/scripts/run.sh"

  # Stub claude (renamed from bin-claude → claude in PATH) records a line per call
  # and emulates synthesis writing PARENT_DIR/index.md.
  cat > "$tmp/bin-claude" <<'STUB'
#!/usr/bin/env bash
echo "synthesis invoked" >> "$SYNTHESIS_LOG"
PARENT_DIR_FROM_PROMPT="$(printf '%s\n' "$@" | grep -oE 'PARENT_DIR: [^ ]+' | head -1 | awk '{print $2}')"
[ -n "$PARENT_DIR_FROM_PROMPT" ] && \
  cat > "$PARENT_DIR_FROM_PROMPT/index.md" <<MD
---
layout: expedition
title: synthesis stub
synthesis: true
---
synthesised
MD
echo '{"total_cost_usd":0.01,"duration_ms":1000,"result":"ok"}'
STUB
  chmod +x "$tmp/bin-claude"
  mv "$tmp/bin-claude" "$tmp/claude"
  echo "$tmp"
}

for n in 0 1 2 3; do
  tmp=$(setup_with_n_successes "$n")
  synthesis_log="$tmp/synthesis.log"
  touch "$synthesis_log"
  PATH="$tmp:$PATH" \
    env PARENT_DIR="$tmp/atlas-checkout/p" \
        PARENT_TOPIC="t" PARENT_FORMAT=md DATE=2026-04-26 \
        SUB_TOPICS_TSV=$'A|standard||true\nB|standard||true\nC|standard||true' \
        SCOUT_DIR="$tmp/scout" \
        SYNTHESIS_LOG="$synthesis_log" \
        bash "$tmp/scout/scripts/run-decompose.sh" >/dev/null 2>&1 || true
  count=$(wc -l < "$synthesis_log" | tr -d ' ')
  expected=0; [ "$n" -ge 2 ] && expected=1
  [ "$count" -eq "$expected" ] && pass "n=$n: synthesis=$expected" \
                              || fail "n=$n: expected synthesis=$expected, got $count"
done

echo
echo "Passed: $PASS, Failed: $FAIL"
[ $FAIL -eq 0 ]
