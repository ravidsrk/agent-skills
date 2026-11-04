#!/usr/bin/env bash
# The pre-push gate: regenerate, lint, typecheck, drift, then the full suite on a fresh database. Each step's full
# log goes to $SCRATCH/gate-<step>.log; the run stops at the first failing step. The printed tail is a pointer,
# not the result: read the whole lint log.
#
# Usage: gate.sh <worktree> [--no-tests]
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,${/^#/!q;s/^# \{0,1\}//p}' "$0"; exit 0;; esac
. "$(dirname "$0")/lib.sh"

wt="$(cd "${1:?usage: gate.sh <worktree> [--no-tests]}" && pwd)"; shift
tests=1; [ "${1:-}" = "--no-tests" ] && tests=0
load_config "$wt" || exit 1
cd "$wt"

step() {
  local name="$1" cmd="$2" log="$SCRATCH/gate-$1.log"
  [ -z "$cmd" ] && { echo "· $name: skipped (not configured)"; return 0; }
  printf '· %s ... ' "$name"
  if bash -c "$cmd" >"$log" 2>&1; then
    echo "ok ($log)"
  else
    echo "FAILED ($log)"; tail -n 25 "$log"; return 1
  fi
}

step regen "${REGEN_CMD:-}" || exit 1
if ! git diff --quiet; then
  echo "· regen changed tracked files: commit them or find why they drifted"; git status --short | head; exit 1
fi
step lint "${LINT_CMD:-}" || exit 1
step typecheck "${TYPECHECK_CMD:-}" || exit 1
i=0
for cmd in "${DRIFT_CMDS[@]:-}"; do
  [ -z "$cmd" ] && continue
  i=$((i + 1)); step "drift-$i" "$cmd" || exit 1
done
if ! git diff --quiet; then
  echo "· drift: a check changed tracked files"; git status --short | head; exit 1
fi
[ "$tests" = 1 ] || { echo "gate passed (tests skipped)"; exit 0; }

step fresh-db "${FRESH_DB_CMD:-}" || exit 1
envload=""
[ -n "${TEST_ENV_FILE:-}" ] && envload="set -a; . '$TEST_ENV_FILE'; set +a; "
if step test "${envload}${TEST_CMD:-}"; then
  echo "gate passed"
else
  echo "test failures: classify each (references/gate.md). Run one alone with: ${TEST_ONE_CMD:-<TEST_ONE_CMD>}"
  exit 1
fi
