#!/usr/bin/env bash
# Tests for scripts/fetch-image.sh — the whole image chain in one allowlistable command.
# curl is PATH-stubbed; ImageMagick is real (it is what the script actually has to drive).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/fetch-image.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

if ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; then
  echo "SKIP: ImageMagick not installed"; exit 0
fi

# A stub curl that serves $STUB_BODY, honouring -o <file> like the real thing.
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
out=""
prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
[ -n "${STUB_RC:-}" ] && [ "$STUB_RC" != "0" ] && exit "$STUB_RC"
if [ -n "$out" ]; then cp "$STUB_BODY" "$out"; else cat "$STUB_BODY"; fi
STUB
chmod +x "$BIN/curl"
run() { PATH="$BIN:$PATH" bash "$SCRIPT" "$@"; }

im() { if command -v magick >/dev/null 2>&1; then magick "$@"; else convert "$@"; fi; }
im_identify() { if command -v magick >/dev/null 2>&1; then magick identify "$@"; else identify "$@"; fi; }

# --- fixtures ---
REAL_PNG="$WORK/real.png"
im -size 400x400 plasma:fractal "$REAL_PNG"          # noisy => comfortably >2KB
REAL_WEBP="$WORK/real.webp"
im "$REAL_PNG" "$REAL_WEBP" 2>/dev/null              # `file` calls this "Web/P image", not "image data"
TINY_PNG="$WORK/tiny.png"
im -size 1x1 xc:white "$TINY_PNG"                    # a real image, but under the 2KB floor
HTML_ERR="$WORK/error.html"
printf '<html><body>404 Not Found</body></html>' > "$HTML_ERR"

cat > "$WORK/commons.json" <<'JSON'
{"query":{"pages":{"1":{"title":"File:Cendol.jpg","imageinfo":[{"thumburl":"https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Cendol.jpg/1200px-Cendol.jpg","url":"https://upload.wikimedia.org/x.jpg","mime":"image/jpeg"}]}}}}
JSON
printf '{"batchcomplete":""}' > "$WORK/commons-empty.json"

cat > "$WORK/og.html" <<'HTML'
<html><head><meta property="og:image" content="https://resto.example/hero.jpg"></head><body>x</body></html>
HTML
cat > "$WORK/og-reversed.html" <<'HTML'
<html><head><meta content="https://resto.example/rev.jpg" property="og:image"></head></html>
HTML
cat > "$WORK/og-twitter.html" <<'HTML'
<html><head><meta name="twitter:image" content="https://resto.example/tw.jpg"></head></html>
HTML
cat > "$WORK/og-none.html" <<'HTML'
<html><head><title>no image here</title></head></html>
HTML

# --- commons ---
got=$(STUB_BODY="$WORK/commons.json" run commons "cendol penang")
[ "$got" = "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Cendol.jpg/1200px-Cendol.jpg" ] \
  && pass "commons: prints the 1200px thumburl" \
  || fail "commons: expected thumburl, got '$got'"

STUB_BODY="$WORK/commons-empty.json" run commons "asdfqwerzxcv" >/dev/null 2>&1 \
  && fail "commons: no results should exit non-zero" \
  || pass "commons: no results exits non-zero"

got=$(STUB_BODY="$WORK/commons-empty.json" run commons "asdfqwerzxcv" 2>/dev/null)
[ -z "$got" ] && pass "commons: no results prints nothing on stdout" \
  || fail "commons: no results leaked stdout: '$got'"

# --- og ---
got=$(STUB_BODY="$WORK/og.html" run og "https://resto.example")
[ "$got" = "https://resto.example/hero.jpg" ] \
  && pass "og: extracts og:image" || fail "og: expected hero.jpg, got '$got'"

got=$(STUB_BODY="$WORK/og-reversed.html" run og "https://resto.example")
[ "$got" = "https://resto.example/rev.jpg" ] \
  && pass "og: extracts content-before-property ordering" || fail "og: reversed order, got '$got'"

got=$(STUB_BODY="$WORK/og-twitter.html" run og "https://resto.example")
[ "$got" = "https://resto.example/tw.jpg" ] \
  && pass "og: falls back to twitter:image" || fail "og: twitter fallback, got '$got'"

STUB_BODY="$WORK/og-none.html" run og "https://resto.example" >/dev/null 2>&1 \
  && fail "og: no meta tag should exit non-zero" \
  || pass "og: no meta tag exits non-zero"

# --- fetch: happy path ---
D="$WORK/views/ledger/images"
got=$(STUB_BODY="$REAL_PNG" run fetch "$D" "hero" "https://x.example/a.png")
[ "$got" = "hero.webp" ] && pass "fetch: prints <slug>.webp" || fail "fetch: expected hero.webp, got '$got'"
[ -f "$D/hero.webp" ] && pass "fetch: writes the webp" || fail "fetch: no webp written"
im_identify "$D/hero.webp" 2>/dev/null | grep -q 'WEBP' \
  && pass "fetch: output is genuinely WebP" || fail "fetch: output is not WebP"
[ ! -f "$D/hero.dl" ] && pass "fetch: removes the .dl temp" || fail "fetch: .dl temp left behind"
[ -d "$D" ] && pass "fetch: creates the images dir" || fail "fetch: dir not created"

# a source that is already WebP must survive (`file` reports "Web/P image", not "image data")
got=$(STUB_BODY="$REAL_WEBP" run fetch "$D" "already" "https://x.example/a.webp")
[ "$got" = "already.webp" ] && [ -f "$D/already.webp" ] \
  && pass "fetch: accepts a WebP source" || fail "fetch: rejected a valid WebP source"

# --- fetch: downscaling ---
BIG="$WORK/big.png"; im -size 3000x2000 plasma:fractal "$BIG"
STUB_BODY="$BIG" run fetch "$D" "big" "https://x.example/big.png" >/dev/null
w=$(im_identify -format '%w' "$D/big.webp" 2>/dev/null)
[ "$w" = "1600" ] && pass "fetch: downscales longest edge to 1600" || fail "fetch: width is '$w', expected 1600"

SMALL="$WORK/small.png"; im -size 800x600 plasma:fractal "$SMALL"
STUB_BODY="$SMALL" run fetch "$D" "small" "https://x.example/small.png" >/dev/null
w=$(im_identify -format '%w' "$D/small.webp" 2>/dev/null)
[ "$w" = "800" ] && pass "fetch: does not upscale a smaller image" || fail "fetch: upscaled to '$w'"

# --- fetch: rejections ---
STUB_BODY="$HTML_ERR" run fetch "$D" "junk" "https://x.example/404" >/dev/null 2>&1 \
  && fail "fetch: an HTML error page should be rejected" \
  || pass "fetch: rejects a non-image body"
[ ! -f "$D/junk.webp" ] && pass "fetch: rejected non-image leaves no webp" || fail "fetch: wrote a webp from HTML"
[ ! -f "$D/junk.dl" ] && pass "fetch: rejected non-image leaves no .dl temp" || fail "fetch: .dl temp left after reject"

STUB_BODY="$TINY_PNG" run fetch "$D" "tiny" "https://x.example/t.png" >/dev/null 2>&1 \
  && fail "fetch: a sub-2KB file should be rejected" \
  || pass "fetch: rejects a sub-2KB file"
[ ! -f "$D/tiny.webp" ] && [ ! -f "$D/tiny.dl" ] \
  && pass "fetch: rejected tiny file leaves nothing behind" || fail "fetch: tiny file left artifacts"

STUB_RC=28 STUB_BODY="$REAL_PNG" run fetch "$D" "timeout" "https://x.example/slow" >/dev/null 2>&1 \
  && fail "fetch: a curl failure should exit non-zero" \
  || pass "fetch: a curl failure exits non-zero"
[ ! -f "$D/timeout.dl" ] && pass "fetch: curl failure leaves no .dl temp" || fail "fetch: .dl temp left after curl failure"

# --- usage ---
run 2>/dev/null && fail "usage: no args should exit non-zero" || pass "usage: no args exits non-zero"
run bogus x 2>/dev/null && fail "usage: unknown subcommand should exit non-zero" || pass "usage: unknown subcommand exits non-zero"

# --- the point of the whole exercise: the skill must not hand-roll the pipeline ---
# An inline curl/convert/rm blob re-prompts for permission on every image, because the
# command text changes with each URL. Regression guard for exactly that.
SKILL="$REPO_ROOT/skills/scout-view-author/SKILL.md"
grep -qE '\brm\b' "$SCRIPT" && pass "script owns the rm (skill no longer needs it)" \
  || fail "script does not contain the rm — did the cleanup move?"
grep -q 'fetch-image.sh' "$SKILL" && pass "skill delegates to fetch-image.sh" \
  || fail "skill does not reference fetch-image.sh"
grep -qE '^\s*(rm|convert|magick|file|stat) ' "$SKILL" \
  && fail "skill still inlines rm/convert/file/stat — the permission prompt is back" \
  || pass "skill inlines no rm/convert/file/stat"
grep -qE 'curl.*-o ' "$SKILL" \
  && fail "skill still inlines a curl download — the permission prompt is back" \
  || pass "skill inlines no curl download"
grep -q 'SCOUT_DIR' "$SKILL" && pass "skill declares SCOUT_DIR as an input" \
  || fail "skill needs SCOUT_DIR to locate the script, but never mentions it"

# Claude Code splits a compound command on && || ; | and permission-checks each part
# separately — so chaining the calls would re-introduce the prompt-per-image.
grep -E '^\s*(bash|url=|IMG=|DIR=).*fetch-image\.sh' "$SKILL" | grep -qE '&&|\|\||\$\(|;' \
  && fail "skill chains fetch-image.sh calls — each subcommand is checked separately, prompt is back" \
  || pass "skill invokes fetch-image.sh as standalone commands (no && || ; \$())"

# both dispatchers must actually pass SCOUT_DIR through, or the skill cannot find the script
grep -q 'SCOUT_DIR' "$REPO_ROOT/scripts/views-dispatch.sh" \
  && pass "views-dispatch passes SCOUT_DIR" || fail "views-dispatch does not pass SCOUT_DIR"
grep -q 'SCOUT_DIR=\$SCOUT_DIR' "$REPO_ROOT/skills/scout/SKILL.md" \
  && pass "local /scout path passes SCOUT_DIR to the view agent" \
  || fail "local /scout path does not pass SCOUT_DIR to the view agent"

# The plugin installs under a versioned dir (…/cache/scout/scout/<version>/), so the
# grant must not pin a version — it would go stale on the next release.
grep -qE '^allowed-tools:.*Bash\(bash \*/scripts/fetch-image\.sh \*\)' "$REPO_ROOT/skills/scout/SKILL.md" \
  && pass "/scout grants fetch-image.sh path-agnostically" \
  || fail "/scout allowed-tools lacks a path-agnostic fetch-image.sh grant"

echo
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '%s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
