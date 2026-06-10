#!/usr/bin/env bash
# Tests for scripts/local-issue.sh — provenance issue helper.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing local-issue.sh..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scoutdir" "$TMP/bin"

# A scout checkout whose origin remote determines the target repo.
git -C "$TMP/scoutdir" init -q
git -C "$TMP/scoutdir" remote add origin git@github.com:Laoujin/Scout.git

# Stub gh: log argv; on create echo a realistic issue URL and dump the body file.
GH_LOG="$TMP/gh.log"; GH_BODY="$TMP/gh.body"
cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "$GH_LOG"
if [ "\$1 \$2" = "issue create" ]; then
  while [ \$# -gt 0 ]; do [ "\$1" = "--body-file" ] && { cp "\$2" "$GH_BODY"; break; }; shift; done
  [ "\${GH_FAIL:-0}" = "1" ] && exit 1
  echo "https://github.com/Laoujin/Scout/issues/77"
fi
exit 0
STUB
chmod +x "$TMP/bin/gh"

PROMPT="$TMP/prompt.txt"
printf 'Build a complete first-visit guide to Hoi An.\nScope: our first-ever trip.\n' > "$PROMPT"

# --- open: creates against the derived repo with verbatim body, prints number ---
NUM="$(PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
       bash "$REPO_ROOT/scripts/local-issue.sh" open "Hoi An guide" "$PROMPT")"
[ "$NUM" = "77" ] && pass "open prints parsed issue number" || fail "open number='$NUM' (want 77)"
grep -q -- "--repo Laoujin/Scout" "$GH_LOG" && pass "create targets repo from remote" || fail "wrong/no repo: $(cat "$GH_LOG")"
grep -qF -- "--title [research-local] Hoi An guide" "$GH_LOG" && pass "create prefixes title with [research-local]" || fail "no prefixed title in: $(cat "$GH_LOG")"
grep -qF -- "--label scout-local-research" "$GH_LOG" && pass "create applies scout-local-research label" || fail "no label in: $(cat "$GH_LOG")"
grep -qF -- "label create scout-local-research" "$GH_LOG" && pass "open ensures the scout-local-research label exists first" || fail "no label-create ensure call in: $(cat "$GH_LOG")"
diff -q "$PROMPT" "$GH_BODY" >/dev/null 2>&1 && pass "issue body is the verbatim prompt" || fail "body not verbatim"

# --- close: comments Published then closes ---
: > "$GH_LOG"
PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
  bash "$REPO_ROOT/scripts/local-issue.sh" close 77 "https://laoujin.github.io/Atlas/research/x/"
grep -q "issue comment 77 --repo Laoujin/Scout --body Published: https://laoujin.github.io/Atlas/research/x/" "$GH_LOG" \
  && pass "close comments the Published URL" || fail "no Published comment: $(cat "$GH_LOG")"
grep -q "issue close 77" "$GH_LOG" && pass "close closes the issue" || fail "issue not closed: $(cat "$GH_LOG")"

# --- non-fatal: gh create failure yields empty number, exit 0 ---
NUM2="$(PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" GH_FAIL=1 \
        bash "$REPO_ROOT/scripts/local-issue.sh" open "T" "$PROMPT")"; RC=$?
[ "$RC" = "0" ] && pass "open exits 0 on gh failure" || fail "open exit=$RC on gh failure"
[ -z "$NUM2" ] && pass "open prints empty number on gh failure" || fail "open printed '$NUM2' on failure"

# --- non-fatal: close with empty number is a no-op ---
: > "$GH_LOG"
PATH="$TMP/bin:$PATH" SCOUT_DIR="$TMP/scoutdir" \
  bash "$REPO_ROOT/scripts/local-issue.sh" close "" "url"
[ ! -s "$GH_LOG" ] && pass "close with empty number does nothing" || fail "close ran gh: $(cat "$GH_LOG")"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
