#!/usr/bin/env bash
# create-series.sh — scaffold a NEW series in Atlas's _data/series.yml and write
# its page stub. Counterpart to add-to-series.sh (which only adds MEMBERS to an
# EXISTING series). Never clobbers: a slug that already exists aborts non-zero.
#
# Usage:
#   create-series.sh <series.yml> <slug> <title> <blurb> \
#       [--cover <url>] [--stub-dir <dir>] [--group <label>]...
#
#   No --group        → flat empty `entries:` list.
#   One+ --group       → `groups:` list, each label with an empty `entries:`.
#   --cover <url>      → adds a `cover:` line (usually omitted; Project 1 resolves
#                        series/<slug>.svg by convention).
#   --stub-dir <dir>   → where to write <slug>.md (default: <atlas-root>/series,
#                        atlas-root = dirname(dirname(series.yml))).
#
# Members are added afterward with add-to-series.sh. The skill authors the cover
# SVG separately at <atlas-root>/series/<slug>.svg.

set -uo pipefail

YAML="${1:?series.yml path required}"
SLUG="${2:?slug required}"
TITLE="${3:?title required}"
BLURB="${4:?blurb required}"
shift 4

COVER=""; STUB_DIR=""; declare -a GROUP_LABELS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cover)    COVER="${2:?--cover needs a value}"; shift 2 ;;
    --stub-dir) STUB_DIR="${2:?--stub-dir needs a value}"; shift 2 ;;
    --group)    GROUP_LABELS+=("${2:?--group needs a value}"); shift 2 ;;
    *) echo "create-series: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -f "$YAML" ] || { echo "create-series: series.yml not found at $YAML" >&2; exit 1; }

# Never clobber: abort if the slug already exists as a top-level series.
if grep -qE "^- slug:[[:space:]]+${SLUG}[[:space:]]*$" "$YAML"; then
  echo "create-series: series '$SLUG' already exists — aborting" >&2
  exit 3
fi

# Emit a YAML-safe scalar: plain unless it would mis-parse, else double-quoted.
yaml_scalar() {
  local v="$1"
  if printf '%s' "$v" | grep -qE '(: )|^[[:space:]]|^[-?:,#&*!|>%@`"'\'']' ; then
    v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    printf '"%s"' "$v"
  else
    printf '%s' "$v"
  fi
}

# Append the new block. EOF append leaves all existing content + comments intact.
{
  printf '\n- slug: %s\n' "$SLUG"
  printf '  title: %s\n' "$(yaml_scalar "$TITLE")"
  printf '  blurb: %s\n' "$(yaml_scalar "$BLURB")"
  [ -n "$COVER" ] && printf '  cover: %s\n' "$COVER"
  if [ "${#GROUP_LABELS[@]}" -gt 0 ]; then
    printf '  groups:\n'
    for g in "${GROUP_LABELS[@]}"; do
      printf '    - label: %s\n' "$(yaml_scalar "$g")"
      printf '      entries:\n'
    done
  else
    printf '  entries:\n'
  fi
} >> "$YAML"

# Write the page stub if absent (never overwrite an existing one).
if [ -z "$STUB_DIR" ]; then
  STUB_DIR="$(cd "$(dirname "$YAML")/.." && pwd)/series"
fi
mkdir -p "$STUB_DIR"
STUB="$STUB_DIR/$SLUG.md"
if [ -e "$STUB" ]; then
  echo "create-series: stub already exists at $STUB — left untouched" >&2
else
  cat > "$STUB" <<EOF
---
layout: series
series_slug: $SLUG
permalink: /series/$SLUG/
---
EOF
fi

echo "create-series: created '$SLUG' (${#GROUP_LABELS[@]} groups) + stub $STUB" >&2
