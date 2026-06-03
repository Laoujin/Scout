#!/usr/bin/env bash
# Tests for scripts/create-series.sh — scaffold a NEW series + stub, never clobber.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/create-series.sh"
ADD="$REPO_ROOT/scripts/add-to-series.sh"
PASS=0; FAIL=0; declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# A minimal Atlas-like layout: <root>/_data/series.yml and <root>/series/.
new_atlas() {
  local root="$1"
  mkdir -p "$root/_data" "$root/series"
  cat > "$root/_data/series.yml" <<'YAML'
# series manifest — keep this header comment.
- slug: michelin-weekends
  title: Michelin weekend getaways
  blurb: Weekends built around a starred restaurant.
  groups:
    - label: Belgium
      entries:
        - 2026-05-23-la-table-de-maxime
YAML
}

# --- grouped series + stub ---
R="$WORK/a"; new_atlas "$R"; Y="$R/_data/series.yml"
bash "$SCRIPT" "$Y" tooling "Tooling & research" "Notes on the tools." --group Research --group Infrastructure
grep -qE '^- slug: tooling$' "$Y"                  && pass "grouped: slug block appended"      || fail "grouped: slug missing"
grep -qE '^  title: Tooling & research$' "$Y"      && pass "grouped: title written"            || fail "grouped: title missing"
grep -qE '^  blurb: Notes on the tools\.$' "$Y"    && pass "grouped: blurb written"            || fail "grouped: blurb missing"
grep -qE '^  groups:$' "$Y"                         && pass "grouped: groups key written"       || fail "grouped: groups missing"
grep -qE '^    - label: Research$' "$Y"             && pass "grouped: label Research written"   || fail "grouped: label Research missing"
grep -qE '^    - label: Infrastructure$' "$Y"       && pass "grouped: label Infrastructure"     || fail "grouped: label Infrastructure missing"
[ "$(awk '/^- slug: tooling$/{p=1} p' "$Y" | grep -cE '^      entries:$')" -eq 2 ] && pass "grouped: two empty entries lists"  || fail "grouped: entries lists wrong count"
grep -qE '^# series manifest' "$Y"                  && pass "grouped: header comment preserved" || fail "grouped: header comment lost"
grep -qE '^- slug: michelin-weekends$' "$Y"         && pass "grouped: existing series preserved"|| fail "grouped: existing series lost"
[ -f "$R/series/tooling.md" ]                       && pass "grouped: stub created"             || fail "grouped: stub missing"
grep -qE '^series_slug: tooling$' "$R/series/tooling.md" && pass "grouped: stub series_slug"    || fail "grouped: stub series_slug wrong"
grep -qE '^permalink: /series/tooling/$' "$R/series/tooling.md" && pass "grouped: stub permalink" || fail "grouped: stub permalink wrong"
grep -qE '^layout: series$' "$R/series/tooling.md"  && pass "grouped: stub layout"              || fail "grouped: stub layout wrong"

# reuse: add-to-series.sh inserts a member into the freshly-scaffolded group
bash "$ADD" "$Y" 2026-06-01-some-entry tooling Research
grep -qE '^        - 2026-06-01-some-entry$' "$Y"   && pass "reuse: add-to-series into new group" || fail "reuse: member not inserted"

# --- flat series ---
R2="$WORK/b"; new_atlas "$R2"; Y2="$R2/_data/series.yml"
bash "$SCRIPT" "$Y2" gift-guides "Gift guides" "Curated present ideas."
awk '/^- slug: gift-guides$/{p=1} p' "$Y2" | grep -qE '^  entries:$' && pass "flat: entries key written" || fail "flat: entries missing"
awk '/^- slug: gift-guides$/{p=1} p' "$Y2" | grep -qE '^  groups:$' && fail "flat: should not have groups" || pass "flat: no groups key"

# --- cover line ---
R3="$WORK/c"; new_atlas "$R3"; Y3="$R3/_data/series.yml"
bash "$SCRIPT" "$Y3" withcover "With Cover" "Has a cover." --cover /series/withcover.svg
grep -qE '^  cover: /series/withcover.svg$' "$Y3"   && pass "cover: cover line written"         || fail "cover: cover line missing"

# --- title needing YAML quoting (contains ': ') ---
R4="$WORK/d"; new_atlas "$R4"; Y4="$R4/_data/series.yml"
bash "$SCRIPT" "$Y4" colon "Scout: the playbook" "A blurb."
grep -qE '^  title: "Scout: the playbook"$' "$Y4"   && pass "quote: colon title double-quoted"  || fail "quote: colon title not quoted"

# --- duplicate slug aborts, file untouched ---
R5="$WORK/e"; new_atlas "$R5"; Y5="$R5/_data/series.yml"
before="$(sha1sum "$Y5" | cut -d' ' -f1)"
bash "$SCRIPT" "$Y5" michelin-weekends "Dup" "Dup." ; rc=$?
after="$(sha1sum "$Y5" | cut -d' ' -f1)"
[ "$rc" -ne 0 ]            && pass "dup: non-zero exit"        || fail "dup: should exit non-zero"
[ "$before" = "$after" ]   && pass "dup: file untouched"       || fail "dup: file was modified"

# --- existing stub not overwritten ---
R6="$WORK/f"; new_atlas "$R6"; Y6="$R6/_data/series.yml"
mkdir -p "$R6/series"; printf 'PRE-EXISTING\n' > "$R6/series/keepme.md"
bash "$SCRIPT" "$Y6" keepme "Keep Me" "Blurb." ; rc=$?
[ "$rc" -eq 0 ]            && pass "stub: exit 0 when stub exists" || fail "stub: should exit 0"
grep -qx 'PRE-EXISTING' "$R6/series/keepme.md" && pass "stub: existing stub untouched" || fail "stub: existing stub overwritten"

echo; echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then printf '  %s\n' "${FAIL_MSGS[@]}"; exit 1; fi
