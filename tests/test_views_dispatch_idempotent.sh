#!/usr/bin/env bash
# Verifies views-dispatch.sh is idempotent: when a ticked row's view file already
# exists in atlas-checkout, no claude invocation happens for that row, and the
# results comment lists it as ⏭ skipped.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Testing views-dispatch.sh idempotency..."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Stub gh: capture every body posted (so we can inspect the results comment),
# emulate gh api PATCH for comment edits, no-op for issue close/reopen.
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  api)
    # Just consume args, do nothing.
    exit 0
    ;;
  issue)
    case "$2" in
      view)
        echo "OPEN"
        ;;
      comment)
        shift 2
        while [ $# -gt 0 ]; do
          if [ "$1" = "--body" ]; then shift; printf '%s\n---SEP---\n' "$1" >> "$CAPTURE_FILE"; shift
          else shift; fi
        done
        ;;
      close|reopen)
        echo "[gh-stub] $2 invoked" >> "$CAPTURE_FILE.events"
        ;;
    esac
    ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"

# Stub claude: append a marker so we can detect any invocation.
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude-invoked: $*" >> "$CLAUDE_LOG"
echo '{"result":"<html>stub view</html>","total_cost_usd":0,"duration_ms":1}'
EOF
chmod +x "$TMP/bin/claude"

# Stub git: no-op for any operation. We aren't testing the real push.
cat > "$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  clone) mkdir -p "$3" ;;
  *) ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/git"

export PATH="$TMP/bin:$PATH"
export CAPTURE_FILE="$TMP/captured-bodies"
export CLAUDE_LOG="$TMP/claude.log"
: > "$CAPTURE_FILE"
: > "$CLAUDE_LOG"

# Pre-populate atlas-checkout with canonical index files and one already-existing
# view file. SCOUT_TEST_KEEP_ATLAS=1 tells views-dispatch.sh to skip rm+clone so
# this fixture survives the script's startup.
ATLAS="$REPO_ROOT/atlas-checkout"
mkdir -p "$ATLAS/research/2026-04-28-high-signal-ai"
echo $'---\ntitle: High-signal AI\n---' > "$ATLAS/research/2026-04-28-high-signal-ai/index.md"
mkdir -p "$ATLAS/research/2026-04-28-high-signal-ai/long-form-bloggers/views"
echo $'---\ntitle: Long-form Bloggers\n---' > "$ATLAS/research/2026-04-28-high-signal-ai/long-form-bloggers/index.md"
echo "<html>existing</html>" > "$ATLAS/research/2026-04-28-high-signal-ai/long-form-bloggers/views/bookshelf.html"

# Bot comment body: parent + long-form-bloggers BOTH ticked. long-form-bloggers
# already has a view, so dispatch must skip it.
BODY="$(cat <<'BODYEOF'
### HTML view candidates

- [x] **High-signal AI software creators** — register: masthead <!-- slug:high-signal-ai -->
- [x] long-form-bloggers — register: bookshelf <!-- slug:long-form-bloggers -->

- [x] **Start creating the HTML pages**

<!-- scout-view-targets-start -->
```scout-view-targets
{"items":[{"row":"parent","slug":"high-signal-ai","path":"research/2026-04-28-high-signal-ai","view_name":"masthead","title_suffix":"Masthead","vibe_hint":"masthead"},{"row":"leaf","slug":"long-form-bloggers","path":"research/2026-04-28-high-signal-ai/long-form-bloggers","view_name":"bookshelf","title_suffix":"Bookshelf","vibe_hint":"shelf"}]}
```
<!-- scout-view-targets-end -->
BODYEOF
)"

ISSUE_NUMBER=99 GH_TOKEN=x GH_REPO=x/y BOT_COMMENT_BODY="$BODY" BOT_COMMENT_ID=12345 \
  ATLAS_REPO="file://$ATLAS" \
  SCOUT_TEST_KEEP_ATLAS=1 \
  bash "$REPO_ROOT/scripts/views-dispatch.sh" >/dev/null 2>&1 || true

# Assertions:
# 1. claude was invoked exactly once (for high-signal-ai), not twice.
CLAUDE_COUNT=$(grep -c '^claude-invoked:' "$CLAUDE_LOG" || echo 0)
if [ "$CLAUDE_COUNT" = "1" ]; then pass "claude invoked once for non-existing view"
else fail "claude invoked $CLAUDE_COUNT times (expected 1)"; fi

# 2. results comment contains "skipped (view already exists)" for long-form-bloggers.
if grep -q "long-form-bloggers.*skipped" "$CAPTURE_FILE"; then
  pass "results comment lists long-form-bloggers as skipped"
else
  fail "results comment did not flag long-form-bloggers as skipped"
fi

# Issue 1 regression: when publish_path returns 2 (nothing staged), no SHIPPED flag,
# no gh issue close.
if [ ! -f "$CAPTURE_FILE.events" ] || ! grep -q "close" "$CAPTURE_FILE.events"; then
  pass "rc=2 from publish_path: gh issue close NOT invoked"
else
  fail "rc=2 from publish_path: gh issue close invoked (should be skipped)"
fi

rm -rf "$ATLAS"

# Issue 2 regression: pipe in vibe_hint should not corrupt field-split.
: > "$CLAUDE_LOG"
: > "$CAPTURE_FILE"
mkdir -p "$ATLAS/research/2026-04-29-pipe-test"
cat > "$ATLAS/research/2026-04-29-pipe-test/index.md" <<'EOF'
---
title: Pipe Test
---
EOF
BODY_PIPE="$(cat <<'BODYEOF'
- [x] **Pipe Test** — register: dashboard <!-- slug:pipe-test -->

- [x] **Start creating the HTML pages**

<!-- scout-view-targets-start -->
```scout-view-targets
{"items":[{"row":"parent","slug":"pipe-test","path":"research/2026-04-29-pipe-test","view_name":"dashboard","title_suffix":"Dashboard","vibe_hint":"foo | bar | baz","row":"parent"}]}
```
<!-- scout-view-targets-end -->
BODYEOF
)"
ISSUE_NUMBER=99 GH_TOKEN=x GH_REPO=x/y BOT_COMMENT_BODY="$BODY_PIPE" BOT_COMMENT_ID=23456 \
  ATLAS_REPO="file://$ATLAS" SCOUT_TEST_KEEP_ATLAS=1 \
  bash "$REPO_ROOT/scripts/views-dispatch.sh" >/dev/null 2>&1 || true

CLAUDE_COUNT=$(grep -c '^claude-invoked:' "$CLAUDE_LOG" || echo 0)
if [ "$CLAUDE_COUNT" = "1" ]; then
  pass "pipe in vibe_hint: claude still invoked once"
else
  fail "pipe in vibe_hint: claude invoked $CLAUDE_COUNT times (expected 1)"
fi

rm -rf "$ATLAS"

echo
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
