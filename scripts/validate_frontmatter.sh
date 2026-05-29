#!/usr/bin/env bash
# Validate (and, where safe, auto-fix) an artifact's YAML frontmatter.
# Usage: validate_frontmatter.sh <artifact-file>
# Exits 0 on valid (or auto-fixed) YAML, 1 on missing frontmatter / unfixable
# parse error / missing file.
#
# Two layers:
#   1. Python yaml.safe_load (when available): full YAML parse. On failure it
#      auto-fixes the documented foot-gun — freeform fields (title, summary,
#      topic, topic_raw) whose values contain unquoted colons or quotes — by
#      re-quoting them in place, then re-parses. A model occasionally ignores
#      the "always double-quote" rule (SKILL.md); fixing beats discarding a
#      run's worth of research over one stray colon.
#   2. Bash heuristic (fallback when Python is absent): detect-only. Catches
#      the same freeform-field patterns and fails the run so the issue is
#      visible, but cannot rewrite.

set -euo pipefail

ARTIFACT="${1:?Usage: validate_frontmatter.sh <file>}"

if [ ! -f "$ARTIFACT" ]; then
  echo "validate_frontmatter.sh: file not found: $ARTIFACT" >&2
  exit 1
fi

# Resolve a real Python (not a Windows Store stub).
PY=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import sys" 2>/dev/null; then
    PY="$cand"; break
  fi
done

# --- Layer 1: Python parse + auto-fix --------------------------------------
if [ -n "$PY" ]; then
  "$PY" - "$ARTIFACT" <<'PYEOF'
import sys, re, json
try:
    import yaml
except ImportError:
    sys.exit(99)  # signal: no yaml module, fall back to bash heuristic

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()
lines = text.split("\n")

# Locate the frontmatter block (first pair of `---` lines).
fm_start = fm_end = None
for i, ln in enumerate(lines):
    if ln.strip() == "---":
        if fm_start is None:
            fm_start = i
        else:
            fm_end = i
            break
if fm_start is None or fm_end is None:
    print("validate_frontmatter.sh: no YAML frontmatter found in %s" % path, file=sys.stderr)
    sys.exit(1)

fm_lines = lines[fm_start + 1:fm_end]


def parse(s):
    try:
        return isinstance(yaml.safe_load(s), dict), None
    except yaml.YAMLError as e:
        return False, e


ok, err = parse("\n".join(fm_lines))
if ok:
    sys.exit(0)  # already valid — leave the file byte-for-byte untouched

FREEFORM = ("title", "summary", "topic", "topic_raw")
field_re = re.compile(r"^(\s*)(" + "|".join(FREEFORM) + r"):[ \t]+(.*\S)[ \t]*$")
fixed, changed = [], False
for ln in fm_lines:
    m = field_re.match(ln)
    if m:
        indent, key, val = m.groups()
        cleanly_quoted = False
        if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or (val[0] == "'" and val[-1] == "'")):
            try:
                cleanly_quoted = isinstance(yaml.safe_load(val), str)
            except yaml.YAMLError:
                cleanly_quoted = False
        if not cleanly_quoted:
            # json.dumps emits a valid double-quoted YAML scalar with correct
            # escaping of quotes/backslashes; the original text is preserved.
            fixed.append("%s%s: %s" % (indent, key, json.dumps(val, ensure_ascii=False)))
            changed = True
            continue
    fixed.append(ln)

if not changed or not parse("\n".join(fixed))[0]:
    print("validate_frontmatter.sh: %s has invalid YAML frontmatter:" % path, file=sys.stderr)
    print("YAML parse error: %s" % err, file=sys.stderr)
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines[:fm_start + 1] + fixed + lines[fm_end:]))
print("validate_frontmatter.sh: auto-fixed freeform-field quoting in %s" % path, file=sys.stderr)
sys.exit(0)
PYEOF
  rc=$?
  # rc 99 == python lacks the yaml module; fall through to the bash heuristic.
  [ "$rc" -ne 99 ] && exit "$rc"
fi

# --- Layer 2: bash heuristic (detect-only fallback) ------------------------
FM="$(awk '
  /^---[[:space:]]*$/ { n++; if (n==2) exit; next }
  n==1 { print }
' "$ARTIFACT")"

if [ -z "$FM" ]; then
  echo "validate_frontmatter.sh: no YAML frontmatter found in $ARTIFACT" >&2
  exit 1
fi

FREEFORM_FIELDS="title|summary|topic|topic_raw"
ERRORS=0
while IFS= read -r line; do
  if printf '%s' "$line" | grep -qE "^[[:space:]]*(${FREEFORM_FIELDS}):[[:space:]]"; then
    value="$(printf '%s' "$line" | sed -E "s/^[[:space:]]*(${FREEFORM_FIELDS}):[[:space:]]*//")"
    [ -z "$value" ] && continue
    printf '%s' "$value" | grep -qE '^".*"$' && continue
    printf '%s' "$value" | grep -qE "^'.*'$" && continue
    field="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*([a-z_]+):.*/\1/')"
    if printf '%s' "$value" | grep -qF ':'; then
      echo "validate_frontmatter.sh: $ARTIFACT: field '$field' contains unquoted colon — wrap in double quotes (install python3+pyyaml to auto-fix)" >&2
      ERRORS=$((ERRORS + 1))
    fi
    if printf '%s' "$value" | grep -qF '"'; then
      echo "validate_frontmatter.sh: $ARTIFACT: field '$field' contains unquoted double quote — wrap value or escape (install python3+pyyaml to auto-fix)" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
done <<< "$FM"

[ "$ERRORS" -gt 0 ] && exit 1
exit 0
