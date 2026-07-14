#!/usr/bin/env bash
# The image chain for scout-view-author, as one command.
#
#   fetch-image.sh commons <subject>            -> prints a 1200px Commons thumburl
#   fetch-image.sh og <page-url>                -> prints the page's og:image / twitter:image
#   fetch-image.sh fetch <dir> <slug> <img-url> -> downloads, verifies, WebP-encodes; prints <slug>.webp
#
# Exit 1 means "this source came up empty, try the next one" — never fatal to the caller.
# Exit 2 is a usage error.
#
# Keeping curl/rm/identify/convert behind one script is deliberate: an inline pipeline of
# them is re-prompted for permission on every image, because the command text changes with
# each URL. One script = one allowlist rule.
set -uo pipefail

UA="Mozilla/5.0"
TIMEOUT=10
MIN_BYTES=2048
MAX_EDGE=1600
QUALITY=80
COMMONS_API="https://commons.wikimedia.org/w/api.php"

# ImageMagick 7 ships `magick`; 6 ships `convert`/`identify`.
im() { if command -v magick >/dev/null 2>&1; then magick "$@"; else convert "$@"; fi; }
im_identify() { if command -v magick >/dev/null 2>&1; then magick identify "$@"; else identify "$@"; fi; }

usage() {
  sed -n '2,8p' "$0" >&2
  exit 2
}

cmd_commons() {
  local subject="${1:-}" url
  [ -n "$subject" ] || usage
  # The UA header is mandatory — Commons answers with an empty body without one.
  url=$(curl -sL --max-time "$TIMEOUT" -A "$UA" --get \
          --data-urlencode "gsrsearch=$subject" \
          "$COMMONS_API?action=query&generator=search&gsrnamespace=6&gsrlimit=5&prop=imageinfo&iiprop=url|mime&iiurlwidth=1200&format=json" \
        | grep -oE '"thumburl":"[^"]+"' | head -1 \
        | sed 's/^"thumburl":"//; s/"$//; s#\\/#/#g')
  [ -n "$url" ] || return 1
  printf '%s\n' "$url"
}

cmd_og() {
  local page="${1:-}" html img
  [ -n "$page" ] || usage
  html=$(curl -sL --max-time "$TIMEOUT" -A "$UA" "$page") || return 1
  # content= may sit on either side of property=/name=, so try both orders.
  img=$(printf '%s' "$html" \
        | grep -oiE '<meta[^>]+(property|name)="(og:image|twitter:image)"[^>]*content="[^"]+"' \
        | head -1 | grep -oiE 'content="[^"]+"' | sed 's/^[Cc]ontent="//; s/"$//')
  if [ -z "$img" ]; then
    img=$(printf '%s' "$html" \
          | grep -oiE '<meta[^>]+content="[^"]+"[^>]*(property|name)="(og:image|twitter:image)"' \
          | head -1 | grep -oiE 'content="[^"]+"' | sed 's/^[Cc]ontent="//; s/"$//')
  fi
  [ -n "$img" ] || return 1
  printf '%s\n' "$img"
}

cmd_fetch() {
  local dir="${1:-}" slug="${2:-}" url="${3:-}"
  [ -n "$dir" ] && [ -n "$slug" ] && [ -n "$url" ] || usage

  mkdir -p "$dir" || return 1
  local tmp="$dir/$slug.dl" out="$dir/$slug.webp"

  if ! curl -sL --max-time "$TIMEOUT" -A "$UA" -o "$tmp" "$url"; then
    rm -f "$tmp"; return 1
  fi

  # Verify before converting. `identify` rather than `file`, because `file` labels WebP
  # "Web/P image" and AVIF "ISO Media" — neither matches an 'image data' grep.
  if ! im_identify -ping "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; return 1
  fi
  if [ "$(wc -c < "$tmp")" -lt "$MIN_BYTES" ]; then
    rm -f "$tmp"; return 1
  fi

  # A raw 4-12MB OG/PNG hero is what makes Atlas slow to publish and pushes it at the
  # 1GB Pages cap; shrink and re-encode at authoring time.
  if ! im "$tmp" -resize "${MAX_EDGE}x${MAX_EDGE}>" -strip -quality "$QUALITY" "$out" 2>/dev/null; then
    echo "fetch-image: WebP encode failed for $slug (is the ImageMagick webp delegate installed?)" >&2
    rm -f "$tmp" "$out"; return 1
  fi

  rm -f "$tmp"
  printf '%s\n' "$slug.webp"
}

case "${1:-}" in
  commons) shift; cmd_commons "$@" ;;
  og)      shift; cmd_og "$@" ;;
  fetch)   shift; cmd_fetch "$@" ;;
  *)       usage ;;
esac
