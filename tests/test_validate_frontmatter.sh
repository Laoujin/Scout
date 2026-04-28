#!/usr/bin/env bash
# Tests for scripts/validate_frontmatter.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/validate_frontmatter.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing validate_frontmatter.sh..."

TMP=$(mktemp -d)

# --- valid: simple frontmatter ---
cat > "$TMP/valid.md" <<'MD'
---
title: "Simple title"
date: 2026-04-28
summary: "A summary."
---
Body text.
MD
bash "$SCRIPT" "$TMP/valid.md" 2>/dev/null \
  && pass "valid: simple frontmatter passes" \
  || fail "valid: simple frontmatter should pass"

# --- valid: title with colon (quoted) ---
cat > "$TMP/colon.md" <<'MD'
---
title: "Slack → Claude Code → PR: end-to-end"
date: 2026-04-28
summary: "Works great."
---
Body.
MD
bash "$SCRIPT" "$TMP/colon.md" 2>/dev/null \
  && pass "valid: quoted colon in title passes" \
  || fail "valid: quoted colon should pass"

# --- valid: title with embedded quotes (escaped) ---
cat > "$TMP/quotes.md" <<'MD'
---
title: "The \"best\" approach to testing"
date: 2026-04-28
summary: "A summary."
---
Body.
MD
bash "$SCRIPT" "$TMP/quotes.md" 2>/dev/null \
  && pass "valid: escaped quotes in title passes" \
  || fail "valid: escaped quotes should pass"

# --- invalid: unquoted colon in title ---
cat > "$TMP/bad_colon.md" <<'MD'
---
title: Slack: the best tool
date: 2026-04-28
summary: A summary.
---
Body.
MD
bash "$SCRIPT" "$TMP/bad_colon.md" 2>/dev/null \
  && fail "invalid: unquoted colon should fail but passed" \
  || pass "invalid: unquoted colon in title caught"

# --- invalid: unquoted value that looks like YAML mapping ---
cat > "$TMP/bad_mapping.md" <<'MD'
---
title: key: value: nested
date: 2026-04-28
---
Body.
MD
bash "$SCRIPT" "$TMP/bad_mapping.md" 2>/dev/null \
  && fail "invalid: nested colons should fail but passed" \
  || pass "invalid: nested colons caught"

# --- failure: no frontmatter ---
cat > "$TMP/no_fm.md" <<'MD'
No frontmatter here at all.
Just body text.
MD
bash "$SCRIPT" "$TMP/no_fm.md" 2>/dev/null \
  && fail "no frontmatter: should fail but passed" \
  || pass "no frontmatter: correctly rejected"

# --- failure: missing file ---
bash "$SCRIPT" "$TMP/nonexistent.md" 2>/dev/null \
  && fail "missing file: should fail but passed" \
  || pass "missing file: correctly rejected"

# --- valid: html frontmatter ---
cat > "$TMP/valid.html" <<'HTML'
---
title: "HTML artifact"
layout: research
summary: "An HTML research page."
---
<h1>Hello</h1>
HTML
bash "$SCRIPT" "$TMP/valid.html" 2>/dev/null \
  && pass "valid: html frontmatter passes" \
  || fail "valid: html frontmatter should pass"

rm -rf "$TMP"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
