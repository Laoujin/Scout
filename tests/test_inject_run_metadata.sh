#!/usr/bin/env bash
# Tests for scripts/inject-run-metadata.sh — deterministic metadata stamping.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
fm() { awk -v k="$2" '/^---$/{n++} n==1 && $0 ~ "^"k":"{sub("^"k":[[:space:]]*","");print;exit}' "$1"; }

echo "Testing inject-run-metadata.sh..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P="$TMP/parent"; mkdir -p "$P/a" "$P/b"

cat > "$P/index.md" <<'MD'
---
layout: expedition
title: Parent
synthesis: true
---
body
MD
cat > "$P/a/index.md" <<'MD'
---
title: A
citations: 5
---
child a
MD
cat > "$P/b/index.md" <<'MD'
---
title: B
citations: 7
---
child b
MD
cat > "$P/manifest.json" <<'JSON'
[
  {"slug":"a","title":"A","depth":"deep","status":"success","start":100,"end":250},
  {"slug":"b","title":"B","depth":"survey","status":"success","start":110,"end":300}
]
JSON

MODEL="Opus 4.8" ISSUE=42 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$P"

# Parent
[ "$(fm "$P/index.md" model)" = '"Opus 4.8"' ] && pass "parent model stamped" || fail "parent model='$(fm "$P/index.md" model)'"
[ "$(fm "$P/index.md" cost_usd)" = '"sub"' ] && pass "parent cost_usd=sub" || fail "parent cost='$(fm "$P/index.md" cost_usd)'"
[ "$(fm "$P/index.md" issue)" = '42' ] && pass "parent issue stamped" || fail "parent issue='$(fm "$P/index.md" issue)'"
[ "$(fm "$P/index.md" duration_sec)" = '200' ] && pass "parent duration=wall-clock (200)" || fail "parent dur='$(fm "$P/index.md" duration_sec)'"

# Children — duration from manifest end-start; model+cost stamped; NO issue
[ "$(fm "$P/a/index.md" duration_sec)" = '150' ] && pass "child a duration=150" || fail "a dur='$(fm "$P/a/index.md" duration_sec)'"
[ "$(fm "$P/b/index.md" duration_sec)" = '190' ] && pass "child b duration=190" || fail "b dur='$(fm "$P/b/index.md" duration_sec)'"
[ "$(fm "$P/a/index.md" model)" = '"Opus 4.8"' ] && pass "child a model stamped" || fail "a model missing"
[ "$(fm "$P/a/index.md" cost_usd)" = '"sub"' ] && pass "child a cost=sub" || fail "a cost missing"
[ -z "$(fm "$P/a/index.md" issue)" ] && pass "child a has NO issue (sub-exempt)" || fail "a issue leaked"

# Idempotency: pre-existing value preserved; re-run is a no-op
before="$(cat "$P/index.md")"
MODEL="Sonnet 4.6" ISSUE=99 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$P" >/dev/null
[ "$(cat "$P/index.md")" = "$before" ] && pass "re-run is a no-op (no overwrite)" || fail "re-run mutated parent"

# Single-pass (no manifest): DURATION env stamps parent
S="$TMP/single"; mkdir -p "$S"
cat > "$S/index.md" <<'MD'
---
title: Single
---
body
MD
MODEL="Opus 4.8" DURATION=321 bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$S"
[ "$(fm "$S/index.md" duration_sec)" = '321' ] && pass "single-pass duration from DURATION env" || fail "single dur='$(fm "$S/index.md" duration_sec)'"

# A manifest child with no index dir must be skipped gracefully (not abort under set -e)
G="$TMP/ghost"; mkdir -p "$G"
cat > "$G/index.md" <<'MD'
---
title: Ghost parent
---
body
MD
cat > "$G/manifest.json" <<'JSON'
[
  {"slug":"missing","title":"Missing","depth":"deep","status":"failed","start":10,"end":20}
]
JSON
if MODEL="Opus 4.8" bash "$REPO_ROOT/scripts/inject-run-metadata.sh" "$G" >/dev/null 2>&1; then
  pass "skips manifest child with no index file (exit 0)"
else
  fail "aborted on manifest child with no index file"
fi
[ "$(fm "$G/index.md" model)" = '"Opus 4.8"' ] && pass "ghost parent still stamped" || fail "ghost parent not stamped"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
