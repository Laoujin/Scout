#!/usr/bin/env bash
# Tests for scripts/inject_cover.sh — wires `cover: cover.svg` into an artifact's
# frontmatter when a cover.svg sits beside it, idempotently. Run:
#   bash tests/test_inject_cover.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INJECTOR="$REPO_ROOT/scripts/inject_cover.sh"

PASS=0; FAIL=0; declare -a FAIL_MSGS
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }

echo "Testing inject_cover.sh..."

newdir() { mktemp -d; }
art_md() {  # $1=dir -> writes index.md with frontmatter, no cover line
  printf -- '---\ntitle: "T"\nmodel: "Sonnet 4.6"\n---\nbody text here\n' > "$1/index.md"
}

# --- Case 1: cover.svg present, no cover: line -> injects inside frontmatter ---
d="$(newdir)"; art_md "$d"; printf '<svg/>' > "$d/cover.svg"
"$INJECTOR" "$d/index.md"; rc=$?
end_fm=$(awk '/^---$/{n++; if(n==2){print NR; exit}}' "$d/index.md")
cov_line=$(awk '/^cover: cover.svg$/{print NR; exit}' "$d/index.md")
if [ "$rc" = "0" ] && [ -n "$cov_line" ] && [ -n "$end_fm" ] && [ "$cov_line" -lt "$end_fm" ]; then
  pass "injects 'cover: cover.svg' inside frontmatter when cover.svg present"
else
  fail "case 1: rc=$rc cov_line='$cov_line' end_fm='$end_fm'"
fi
rm -rf "$d"

# --- Case 2: idempotent — existing cover: line is not duplicated ---
d="$(newdir)"
printf -- '---\ntitle: "T"\ncover: cover.svg\n---\nbody\n' > "$d/index.md"
printf '<svg/>' > "$d/cover.svg"
"$INJECTOR" "$d/index.md"; rc=$?
n=$(grep -c '^cover:' "$d/index.md")
[ "$rc" = "0" ] && [ "$n" = "1" ] && pass "idempotent: does not duplicate existing cover:" \
  || fail "case 2: rc=$rc cover-line-count=$n"
rm -rf "$d"

# --- Case 3: no cover.svg on disk -> no cover: added, exit 0 (skip) ---
d="$(newdir)"; art_md "$d"
"$INJECTOR" "$d/index.md"; rc=$?
grep -q '^cover:' "$d/index.md" \
  && fail "case 3: must not add cover: when no cover.svg exists" \
  || { [ "$rc" = "0" ] && pass "no cover.svg: leaves frontmatter untouched, exits 0" \
       || fail "case 3: expected exit 0, got $rc"; }
rm -rf "$d"

# --- Case 4: html artifact works too ---
d="$(newdir)"
printf -- '---\ntitle: "T"\n---\n<p>body</p>\n' > "$d/index.html"
printf '<svg/>' > "$d/cover.svg"
"$INJECTOR" "$d/index.html"; rc=$?
[ "$rc" = "0" ] && grep -q '^cover: cover.svg$' "$d/index.html" \
  && pass "html: injects cover into frontmatter" || fail "case 4: rc=$rc"
rm -rf "$d"

# --- Case 5: missing file -> exit 1 ---
"$INJECTOR" "/nonexistent/index.md" >/dev/null 2>&1
[ "$?" = "1" ] && pass "missing file: exits 1" || fail "case 5: expected exit 1"

# --- Case 6: no frontmatter -> exit 1 ---
d="$(newdir)"; printf 'no frontmatter here\n' > "$d/index.md"; printf '<svg/>' > "$d/cover.svg"
"$INJECTOR" "$d/index.md" >/dev/null 2>&1
[ "$?" = "1" ] && pass "no frontmatter: exits 1" || fail "case 6: expected exit 1"
rm -rf "$d"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
