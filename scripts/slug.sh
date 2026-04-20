#!/usr/bin/env bash
# Slugify a string: lowercase, strip diacritics, non-alphanumerics -> '-',
# collapse consecutive dashes, strip leading/trailing dashes, truncate to 50 chars.
# Usage: slugify "Some String" -> "some-string"

slugify() {
  local input="$1"
  local s
  s="$(printf '%s' "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$input")"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')"
  s="$(printf '%s' "$s" | sed -E 's/[^a-z0-9]+/-/g')"
  s="$(printf '%s' "$s" | sed -E 's/-+/-/g; s/^-//; s/-$//')"
  s="${s:0:50}"
  s="${s%-}"
  printf '%s' "$s"
}
