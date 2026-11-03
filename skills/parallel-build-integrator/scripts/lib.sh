#!/usr/bin/env bash
# Shared helpers: load the project's .integrator/config.sh and match paths against globs.

SKILL_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# load_config <worktree>: sources <worktree>/.integrator/config.sh (or $INTEGRATOR_CONFIG) and sets defaults.
load_config() {
  local wt="$1" cfg="${INTEGRATOR_CONFIG:-$1/.integrator/config.sh}"
  if [ ! -f "$cfg" ]; then
    echo "no config at $cfg: copy templates/config.sh from the skill to .integrator/config.sh" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$cfg"
  SCRATCH="${SCRATCH:-$HOME/.integrator-scratch}"
  mkdir -p "$SCRATCH"
  UNION_GLOBS="${UNION_GLOBS:-}"
  ROW_GLOBS="${ROW_GLOBS:-}"
  KEYSCAN_ALLOW="${KEYSCAN_ALLOW:-}"
}

# matches_any <path> <space-separated globs>
matches_any() {
  local p="$1" g
  for g in $2; do
    # shellcheck disable=SC2053
    [[ "$p" == $g ]] && return 0
  done
  return 1
}

no_markers() {
  ! git grep -qn -e '^<<<<<<< ' -e '^||||||| ' -e '^>>>>>>> ' -- . ':!*.lock'
}
