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
