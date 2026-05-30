#!/usr/bin/env bash
# Tests for scripts/add-to-series.sh — comment-preserving, idempotent, fail-soft.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/add-to-series.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

make_yaml() {
  cat > "$1" <<'YAML'
# series manifest — keep this header comment.
- slug: michelin-weekends
  title: Michelin weekend getaways
  blurb: Weekends built around a starred restaurant.
  groups:
    - label: Belgium
      entries:
        - 2026-05-23-la-table-de-maxime
    - label: Germany
      entries:
        - 2026-05-27-sonnora

- slug: sessions-and-workshops
  title: Sessions & workshops
  blurb: Talks and workshops.
  entries:
    - 2026-05-23-vibe-coding
YAML
}

# --- insert under an existing group ---
Y="$WORK/a.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
grep -qE '^        - 2026-05-29-munich$' "$Y" \
  && pass "grouped: entry inserted at 8-space indent" \
  || fail "grouped: entry not inserted correctly"
gline=$(grep -n 'label: Germany' "$Y" | cut -d: -f1)
eline=$(grep -n '2026-05-29-munich' "$Y" | cut -d: -f1)
[ "$eline" -gt "$gline" ] && pass "grouped: placed under Germany" || fail "grouped: wrong group"
grep -q '# series manifest — keep this header comment.' "$Y" \
  && pass "grouped: header comment preserved" || fail "grouped: header comment lost"

# --- insert into a flat series ---
Y="$WORK/b.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-mcp-session" sessions-and-workshops
grep -qE '^    - 2026-05-29-mcp-session$' "$Y" \
  && pass "flat: entry inserted at 4-space indent" \
  || fail "flat: entry not inserted correctly"

# --- idempotent: re-run is a no-op (no duplicate) ---
Y="$WORK/c.yml"; make_yaml "$Y"
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
bash "$SCRIPT" "$Y" "2026-05-29-munich" michelin-weekends Germany
cnt=$(grep -c '2026-05-29-munich' "$Y")
[ "$cnt" -eq 1 ] && pass "idempotent: single occurrence" || fail "idempotent: $cnt occurrences"

# --- missing series: soft-skip, file unchanged, exit 0 ---
Y="$WORK/d.yml"; make_yaml "$Y"; before=$(md5sum "$Y" | cut -d' ' -f1)
SOFT="$WORK/soft.log"
SOFT_FAIL_LOG="$SOFT" bash "$SCRIPT" "$Y" "2026-05-29-x" no-such-series; rc=$?
after=$(md5sum "$Y" | cut -d' ' -f1)
[ "$rc" -eq 0 ] && pass "missing series: exit 0" || fail "missing series: exit $rc"
[ "$before" = "$after" ] && pass "missing series: file unchanged" || fail "missing series: file mutated"
grep -q 'series:' "$SOFT" && pass "missing series: logged to SOFT_FAIL_LOG" || fail "missing series: not logged"

# --- missing group: soft-skip ---
Y="$WORK/e.yml"; make_yaml "$Y"; before=$(md5sum "$Y" | cut -d' ' -f1)
bash "$SCRIPT" "$Y" "2026-05-29-x" michelin-weekends Nowhere; rc=$?
after=$(md5sum "$Y" | cut -d' ' -f1)
[ "$rc" -eq 0 ] && [ "$before" = "$after" ] \
  && pass "missing group: exit 0, unchanged" || fail "missing group: rc=$rc changed?"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
