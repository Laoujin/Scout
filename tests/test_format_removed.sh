#!/usr/bin/env bash
# Verifies user-facing `format` has been stripped:
# 1. parse_issue_body defaults FORMAT=auto when no Format section is present.
# 2. parse_issue_body still defaults FORMAT=auto when a (legacy) Format section is present.
# 3. issue-comment.sh rendered output never contains "format:".
# 4. sharpen.sh prompt input never contains "Format:".

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib-issue-parse.sh"

PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$label"
  else fail "$label: expected [$expected], got [$actual]"; fi
}
assert_no_match() {
  local label="$1" pattern="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qiE "$pattern"; then
    fail "$label: pattern [$pattern] matched in output"
  else
    pass "$label"
  fi
}

echo "Testing format removal..."

# 1. No Format section → FORMAT=auto
BODY=$'### Topic\n\nfoo\n\n### Depth\n\nsurvey\n\n### Options\n\n- [ ] Skip sharpening (use my topic verbatim)\n'
parse_issue_body "$BODY"
assert_eq "no Format section: FORMAT=auto" "auto" "$FORMAT"

# 2. Legacy Format section ignored → FORMAT=auto
BODY=$'### Topic\n\nfoo\n\n### Depth\n\nsurvey\n\n### Format\n\nhtml\n\n### Options\n\n- [ ] Skip sharpening (use my topic verbatim)\n'
parse_issue_body "$BODY"
assert_eq "legacy Format ignored: FORMAT=auto" "auto" "$FORMAT"

# 3. issue-comment.sh body contains no "format:"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/skills/scout" "$TMP/bin"
# Stub gh so the script doesn't actually post; capture the body via env.
cat > "$TMP/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Capture the --body argument to a file the test reads.
while [ $# -gt 0 ]; do
  case "$1" in
    --body) shift; printf '%s' "$1" > "$CAPTURE_FILE"; shift ;;
    *) shift ;;
  esac
done
GHSTUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export CAPTURE_FILE="$TMP/captured-body"

ISSUE_NUMBER=1 SHARPENED_TOPIC="hello" DEPTH=standard DEPTH_LABEL=survey \
  GH_TOKEN=x GH_REPO=x/y \
  bash "$REPO_ROOT/scripts/issue-comment.sh"
BODY="$(cat "$CAPTURE_FILE")"
assert_no_match "issue-comment narrow body: no format:" 'format:' "$BODY"

ISSUE_NUMBER=1 \
  SHARPENED_TOPIC=$'hello\n\n```scout-subtopics\n- [x] (survey) **A** — r.\n```\n' \
  DEPTH=standard DEPTH_LABEL=survey GH_TOKEN=x GH_REPO=x/y \
  bash "$REPO_ROOT/scripts/issue-comment.sh"
BODY="$(cat "$CAPTURE_FILE")"
assert_no_match "issue-comment decompose body: no format:" 'format:' "$BODY"

# 4. sharpen.sh prompt construction contains no "Format:"
# Stub claude to capture the positional prompt argument.
cat > "$TMP/bin/claude" <<'CLAUDESTUB'
#!/usr/bin/env bash
# Last positional arg is the prompt input.
echo "$@" > "$CAPTURE_FILE.args"
echo "stub-output"
CLAUDESTUB
chmod +x "$TMP/bin/claude"
RAW_TOPIC="hello" DEPTH=standard SCOUT_PROFILE_FILE=/dev/null \
  bash "$REPO_ROOT/scripts/sharpen.sh" >/dev/null
ARGS="$(cat "$CAPTURE_FILE.args" 2>/dev/null || true)"
assert_no_match "sharpen.sh prompt: no Format:" 'Format:' "$ARGS"

echo
echo "Results: $PASS pass, $FAIL fail"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
