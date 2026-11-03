#!/usr/bin/env bash
# Integrate an owner's hand-back in a side worktree of the integration branch, so a full test run in the
# integration worktree keeps going. On success, prints the fast-forward command to run in the integration worktree.
#
# Usage: integrate.sh <integration-worktree> <side-name> <sha|range>...
#   e.g. integrate.sh "$SCRATCH/integ" cli 359bb84^..85bd168 c8e6833
set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ $# -ge 3 ] || { sed -n '2,7p' "$0"; exit 2; }
integ="$(cd "$1" && pwd)"; name="$2"; shift 2
load_config "$integ"

side="$SCRATCH/integ-$name"
branch="integ-$name"
[ -e "$side" ] && { echo "$side exists: remove it (git worktree remove --force $side) or pick another name"; exit 1; }

cd "$integ"
git worktree add -q -b "$branch" "$side" HEAD
cd "$side"
base_sha=$(git rev-parse HEAD)
if [ -n "${REGEN_CMD:-}" ]; then bash -c "$REGEN_CMD" >"$SCRATCH/integ-$name-regen.log" 2>&1 || true; fi

commits=()
for spec in "$@"; do
  if [[ "$spec" == *..* ]]; then
    while read -r c; do commits+=("$c"); done < <(git rev-list --reverse "$spec")
  else
    commits+=("$spec")
  fi
done

for c in "${commits[@]}"; do
  if ! git -c core.hooksPath=/dev/null cherry-pick "$c" >/dev/null 2>&1; then
    if ! bash "$SKILL_SCRIPTS/merge_loop.sh"; then
      echo "STOPPED at $c in $side: resolve there, run merge_loop.sh, then re-run with the remaining commits"
      exit 1
    fi
  fi
done

no_markers || { echo "markers left in $side"; exit 1; }

# Cherry-picks keep the owner agent's author and trailers: re-author each commit as the repository's configured user.
if [ "${REAUTHOR:-1}" = 1 ] && [ "$(git rev-parse HEAD)" != "$base_sha" ]; then
  GIT_SEQUENCE_EDITOR=true git -c core.hooksPath=/dev/null rebase -q --exec "bash '$SKILL_SCRIPTS/reauthor.sh'" "$base_sha"
fi
echo "authors: $(git log --format='%an <%ae>' "$base_sha"..HEAD | sort -u | tr '\n' ' ')"
echo "integrated ${#commits[@]} commits on $branch ($(git rev-parse --short HEAD)) in $side"
echo "next: run the gate in $side, then in $integ: git merge --ff-only $branch && git worktree remove --force $side && git branch -D $branch"
