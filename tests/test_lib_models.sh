#!/usr/bin/env bash
# Tests for scripts/lib-models.sh — model tiering: defaults, depth map, and the
# env override precedence (per-tier var > lib default; SCOUT_MODEL collapses all).
# Run: bash tests/test_lib_models.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib-models.sh"
PASS=0; FAIL=0
declare -a FAIL_MSGS
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL_MSGS+=("$1"); FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# Run an assertion in a clean subshell so each case controls the env that the
# lib's `:=` defaults see at source time. Echoes the resolved value.
resolve() { # args: <depth>  env: any SCOUT_MODEL* overrides
  source "$LIB"
  scout_model_for_depth "$1"
}

eq() { # <actual> <expected> <msg>
  [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', want '$2')"
}

# --- sensible defaults -----------------------------------------------------
eq "$( resolve ceo )"      haiku  "default: ceo -> haiku"
eq "$( resolve standard )" sonnet "default: standard -> sonnet"
eq "$( resolve deep )"     opus   "default: deep -> opus"

# --- unknown / empty depth falls back to the base tier ---------------------
eq "$( resolve bogus )"    sonnet "unknown depth -> base (sonnet)"
eq "$( resolve '' )"       sonnet "empty depth -> base (sonnet)"

# --- per-tier override beats the default -----------------------------------
eq "$( export SCOUT_MODEL_BASE=opus; resolve standard )" opus \
   "SCOUT_MODEL_BASE override applies to standard"
eq "$( export SCOUT_MODEL_CHEAP=sonnet; resolve ceo )" sonnet \
   "SCOUT_MODEL_CHEAP override applies to ceo"
# An override of one tier must not bleed into the others.
eq "$( export SCOUT_MODEL_BASE=opus; resolve ceo )" haiku \
   "SCOUT_MODEL_BASE override does not affect ceo"

# --- global SCOUT_MODEL collapses every tier -------------------------------
eq "$( export SCOUT_MODEL=sonnet; resolve ceo )"      sonnet "SCOUT_MODEL collapses ceo"
eq "$( export SCOUT_MODEL=sonnet; resolve standard )" sonnet "SCOUT_MODEL collapses standard"
eq "$( export SCOUT_MODEL=sonnet; resolve deep )"     sonnet "SCOUT_MODEL collapses deep"

# --- empty env (as GitHub renders an unset vars.*) keeps the default -------
eq "$( export SCOUT_MODEL_BASE=; resolve standard )" sonnet \
   "empty SCOUT_MODEL_BASE (unset vars.*) -> default sonnet"

# --- friendly model labels (footer display) --------------------------------
lbl() { source "$LIB"; scout_model_label "$1"; }
eq "$( lbl claude-opus-4-8 )"           "Opus 4.8"   "label: opus id -> Opus 4.8"
eq "$( lbl claude-sonnet-4-6 )"         "Sonnet 4.6" "label: sonnet id -> Sonnet 4.6"
eq "$( lbl claude-haiku-4-5-20251001 )" "Haiku 4.5"  "label: haiku id (date suffix) -> Haiku 4.5"
eq "$( lbl 'claude-opus-4-7[1m]' )"     "Opus 4.7"   "label: 1M-context variant suffix stripped"
eq "$( lbl sonnet )"                    "Sonnet"     "label: tier alias -> Sonnet"
eq "$( lbl '' )"                        ""           "label: empty -> empty"

# --- summary ---------------------------------------------------------------
echo
echo "lib-models: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf '  - %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
