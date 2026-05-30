#!/usr/bin/env bash
# add-to-series.sh — idempotently add a research entry to an EXISTING series in
# Atlas's _data/series.yml. Comment-preserving text insert. Never creates a new
# series or group. Fail-soft: any miss logs and exits 0 (never blocks publish).
#
# Usage: add-to-series.sh <series.yml> <entry-slug> <series-slug> [group-label]

set -uo pipefail

YAML="${1:?series.yml path required}"
ENTRY="${2:?entry slug required}"
SERIES="${3:?series slug required}"
GROUP="${4:-}"

soft_fail() {
  echo "add-to-series: $1 — skipping" >&2
  [ -n "${SOFT_FAIL_LOG:-}" ] && echo "series: $1" >> "$SOFT_FAIL_LOG"
  exit 0
}

[ -f "$YAML" ] || soft_fail "series.yml not found at $YAML"

# Idempotent: entry already a member anywhere in the file.
if grep -qE "^[[:space:]]*-[[:space:]]+${ENTRY}[[:space:]]*$" "$YAML"; then
  echo "add-to-series: $ENTRY already present — no-op" >&2
  exit 0
fi

trap 'rm -f "${tmp:-}"' EXIT
tmp="$(mktemp)"
awk -v series="$SERIES" -v group="$GROUP" -v entry="$ENTRY" '
  function indent(s){ match(s, /^ */); return RLENGTH }
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  { lines[NR] = $0 }
  END {
    n = NR
    s_start = 0
    for (i = 1; i <= n; i++) if (trim(lines[i]) == ("- slug: " series)) { s_start = i; break }
    if (!s_start) exit 10
    s_end = n + 1
    for (i = s_start + 1; i <= n; i++) if (lines[i] ~ /^- /) { s_end = i; break }

    e_line = 0
    if (group != "") {
      g_start = 0
      for (i = s_start + 1; i < s_end; i++) if (trim(lines[i]) == ("- label: " group)) { g_start = i; break }
      if (!g_start) exit 11
      g_ind = indent(lines[g_start])
      g_end = s_end
      for (i = g_start + 1; i < s_end; i++)
        if (indent(lines[i]) == g_ind && trim(lines[i]) ~ /^- label:/) { g_end = i; break }
      for (i = g_start + 1; i < g_end; i++) if (trim(lines[i]) == "entries:") { e_line = i; break }
    } else {
      for (i = s_start + 1; i < s_end; i++) if (trim(lines[i]) == "entries:") { e_line = i; break }
    }
    if (!e_line) exit 12

    entry_ind = indent(lines[e_line]) + 2
    ins_after = e_line
    for (i = e_line + 1; i <= n; i++) {
      if (lines[i] ~ /^[[:space:]]*$/) continue
      if (lines[i] ~ /^ *- / && indent(lines[i]) == entry_ind) ins_after = i
      else break
    }
    pad = sprintf("%*s", entry_ind, "")

    for (i = 1; i <= n; i++) {
      print lines[i]
      if (i == ins_after) print pad "- " entry
    }
  }
' "$YAML" > "$tmp"
rc=$?

case "$rc" in
  0)  mv "$tmp" "$YAML" ;;
  10) rm -f "$tmp"; soft_fail "series '$SERIES' not found" ;;
  11) rm -f "$tmp"; soft_fail "group '$GROUP' not found in series '$SERIES'" ;;
  12) rm -f "$tmp"; soft_fail "no entries: list found for series '$SERIES'" ;;
  *)  rm -f "$tmp"; soft_fail "awk failed (rc=$rc)" ;;
esac

echo "add-to-series: added $ENTRY to $SERIES${GROUP:+ › $GROUP}" >&2
