#!/usr/bin/env bash
# Continue an in-progress cherry-pick, resolving append-only files (UNION_GLOBS) with union.py and keyed tables
# (ROW_GLOBS) with merge_rows.py. Stops, exit 1, on any other conflicting file, on an unresolved or duplicated
# row, or on a conflict marker left anywhere. Run it from the worktree root.
#
# Usage: merge_loop.sh
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,${/^#/!q;s/^# \{0,1\}//p}' "$0"; exit 0;; esac
. "$(dirname "$0")/lib.sh"
load_config "$PWD" || exit 1

for _ in $(seq 1 200); do
  git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null || { echo "cherry-pick done"; exit 0; }
  conflicted=$(git diff --name-only --diff-filter=U)
  if [ -n "$conflicted" ]; then
    echo "-- $(git log --oneline -1 CHERRY_PICK_HEAD)"
    manual=""
    for f in $conflicted; do
      if matches_any "$f" "$UNION_GLOBS"; then
        git checkout --conflict=diff3 -- "$f" && python3 "$SKILL_SCRIPTS/union.py" "$f" && git add -- "$f" || manual="$manual $f"
      elif matches_any "$f" "$ROW_GLOBS"; then
        git checkout --conflict=diff3 -- "$f" && python3 "$SKILL_SCRIPTS/merge_rows.py" "$f" && git add -- "$f" || manual="$manual $f"
      else
        manual="$manual $f"
      fi
    done
    if [ -n "$manual" ]; then
      echo "MANUAL:$manual (resolve, git add, then run merge_loop.sh again)"
      exit 1
    fi
  fi
  if ! no_markers; then
    echo "MARKERS LEFT:"
    git grep -n -e '^<<<<<<< ' -e '^||||||| ' -e '^>>>>>>> ' -- . ':!*.lock' | head
    exit 1
  fi
  # Commit hooks run in the gate later; a hook that needs deps the side worktree lacks must not block the pick.
  if ! GIT_EDITOR=true git -c core.hooksPath=/dev/null cherry-pick --continue >/dev/null 2>&1; then
    git diff --name-only --diff-filter=U | grep -q . || { echo "cherry-pick --continue failed"; exit 1; }
  fi
done
echo "too many iterations"; exit 1
