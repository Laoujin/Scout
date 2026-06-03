#!/usr/bin/env bash
# Single source of truth for which Claude model each research step uses. Change a
# tier here, never in the callers. Sourced by run.sh, run-decompose.sh,
# view-candidacy.sh, sharpen.sh, views-dispatch.sh.
#
# Values are Claude Code model aliases (`haiku`/`sonnet`/`opus`), so the resolved
# version follows the CLI and never needs editing here. Pin a full id
# (e.g. claude-sonnet-4-6) only if you need runs reproducible across CLI updates.
#
# Override precedence (high -> low):
#   1. SCOUT_MODEL=<x>            force every tier to one model (e.g. month-end clamp)
#   2. SCOUT_MODEL_{CHEAP,BASE,DEEP}=<x>   override a single tier
#   3. the defaults below
#
# `:=` substitutes when the var is unset OR empty, so an unset GitHub `vars.*`
# (which renders as "") correctly falls through to the default.
: "${SCOUT_MODEL_CHEAP:=haiku}"   # bounded classification (view candidacy)
: "${SCOUT_MODEL_BASE:=sonnet}"   # default research + synthesis
: "${SCOUT_MODEL_DEEP:=opus}"     # contested, multi-source synthesis

# A global SCOUT_MODEL collapses every tier to one model.
if [ -n "${SCOUT_MODEL:-}" ]; then
  SCOUT_MODEL_CHEAP="$SCOUT_MODEL"
  SCOUT_MODEL_BASE="$SCOUT_MODEL"
  SCOUT_MODEL_DEEP="$SCOUT_MODEL"
fi

# Map a research DEPTH (internal code: ceo|standard|deep) to a model tier.
scout_model_for_depth() {
  case "${1:-}" in
    ceo)  echo "$SCOUT_MODEL_CHEAP" ;;
    deep) echo "$SCOUT_MODEL_DEEP"  ;;
    *)    echo "$SCOUT_MODEL_BASE"  ;;
  esac
}

_scout_cap() { local s="${1:-}"; [ -z "$s" ] && return 0; printf '%s%s\n' "$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')" "${s:1}"; }

# Friendly display label for a resolved model id or a tier alias. Used to stamp
# the model into research frontmatter so the Atlas footer can show it.
#   claude-opus-4-8 -> "Opus 4.8"   claude-sonnet-4-6 -> "Sonnet 4.6"
#   claude-haiku-4-5-20251001 -> "Haiku 4.5"   sonnet -> "Sonnet"   "" -> ""
scout_model_label() {
  local m="${1:-}" fam rest major minor
  case "$m" in
    "") return 0 ;;
    claude-*)
      rest="${m#claude-}"          # opus-4-8 | haiku-4-5-20251001
      fam="${rest%%-*}"            # opus
      rest="${rest#"$fam"-}"       # 4-8 | 4-5-20251001
      major="${rest%%-*}"          # 4
      rest="${rest#"$major"-}"     # 8 | 5-20251001
      minor="${rest%%-*}"          # 8 | 5
      if [ "$rest" = "$major" ] || [ -z "$minor" ]; then
        printf '%s %s\n' "$(_scout_cap "$fam")" "$major"
      else
        printf '%s %s.%s\n' "$(_scout_cap "$fam")" "$major" "$minor"
      fi
      ;;
    *) _scout_cap "$m" ;;          # tier alias (sonnet/opus/haiku)
  esac
}

# Pick the model that did the most output work from a Claude result JSON's
# `modelUsage` map (ignores tiny side-calls like the illustrator's haiku) and
# return its friendly label. Empty if the file/field is absent. Needs jq.
scout_model_label_from_result() {
  local f="${1:-}" id=""
  [ -f "$f" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  id="$(jq -r '(.modelUsage // {}) | to_entries | max_by(.value.outputTokens // 0) | .key // empty' "$f" 2>/dev/null || true)"
  scout_model_label "$id"
}
