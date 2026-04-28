#!/usr/bin/env bash
# Slugify a string: lowercase, strip diacritics, non-alphanumerics -> '-',
# collapse consecutive dashes, strip leading/trailing dashes, cap length.
# Usage: slugify "Some String"      -> "some-string"
#        slugify "Some String" 60   -> truncated to 60 chars at word boundary

SLUG_MAX_LENGTH="${SLUG_MAX_LENGTH:-120}"

slugify() {
  local input="$1"
  local max_len="${2:-$SLUG_MAX_LENGTH}"
  local s
  s="$(printf '%s' "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$input")"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g')"
  s="$(printf '%s' "$s" | sed -E 's/-+/-/g; s/^-//; s/-$//')"
  if [ "${#s}" -gt "$max_len" ]; then
    s="${s:0:$max_len}"
    # Prefer cutting at a word (dash) boundary for readability.
    local trimmed="${s%-*}"
    # Use the boundary cut only if it retains at least half the max length;
    # otherwise keep the hard cut to avoid overly short slugs.
    if [ "${#trimmed}" -ge $(( max_len / 2 )) ]; then
      s="$trimmed"
    fi
    s="${s%-}"
  fi
  printf '%s' "$s"
}
