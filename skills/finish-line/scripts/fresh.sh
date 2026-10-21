#!/usr/bin/env bash
# fresh.sh — set every previous Finish Line run aside and start the review over.
#
#   fresh.sh [repo]                      default repo: current directory
#
# For a run that misread the product: its audit, ledger, tests, research notes and code
# changes all build on that reading, so the next run must see none of them. Nothing is
# deleted and no history is rewritten:
#   - the old run stays reachable at branch finish-line-archive/<UTC stamp>
#   - one new commit on finish-line, "chore(finish): fresh start", puts the tree back to the
#     default branch as it is now (the product as you wrote it), minus .finish/ and Finish
#     Line's own tests (finish/ test directories and the old ledger's specs). When the default
#     branch has moved on, that commit also merges it, so the draft PR shows no stale changes.
#     Off the finish-line branch (an old run merged into main), only those paths are removed.
#   - ignored leftovers in .finish/ (evidence, logs) move to .git/finish-line-archive/<stamp>/
# The next session starts at Phase 0 and builds its understanding of the product from the docs.
# finish.sh --fresh runs this, and finish.sh runs it on its own for a run an older version of
# the skill started (no .finish/RUN), unless FINISH_KEEP_RUN=1.
#
# Exit 0 = done, or nothing to clear · 1 = refused (uncommitted changes, detached HEAD,
# a finish.sh run is active)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git jq

case "${1:-}" in -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;; esac
if [[ -n "${1:-}" ]]; then cd "$1" 2>/dev/null || { echo "fresh.sh: no such directory: $1" >&2; exit 1; }; fi

refuse() { echo "fresh.sh: $*" >&2; exit 1; }
say() { echo "${FINISH_FRESH_PREFIX:-}$*"; }
gitc() { # git with the configured identity, if one was given
  if [[ -n "${FINISH_GIT_NAME:-}" && -n "${FINISH_GIT_EMAIL:-}" ]]; then
    git -c user.name="$FINISH_GIT_NAME" -c user.email="$FINISH_GIT_EMAIL" "$@"
  else
    git "$@"
  fi
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || refuse "not inside a git repository"
cd "$(git rev-parse --show-toplevel)" || exit 1
GITDIR="$(cd "$(git rev-parse --git-dir)" && pwd)"
git rev-parse -q --verify HEAD >/dev/null || refuse "no commits yet"
cur="$(git symbolic-ref -q --short HEAD)" || refuse "detached HEAD: check out a branch first"
if [[ -d "$GITDIR/finish-line.lock" && "${FINISH_FRESH_UNDER_RUNNER:-}" != 1 ]]; then
  refuse "a finish.sh run is active in this repo; stop it first, or use finish.sh --fresh"
fi
# Env files hold the owner's keys and logs are being written: neither counts as a change.
if git status --porcelain -uall -- . ':(exclude,glob)**/.env' ':(exclude,glob)**/.env.*' 2>/dev/null | grep -qv ' \.finish/logs/'; then
  refuse "uncommitted changes: commit or stash them first (finish.sh --fresh stashes them for you)"
fi

# The default branch as it is now: origin/HEAD's name, else main/master/trunk/develop; local or
# remote, whichever is ahead (local when they've diverged).
name=""
h="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)" && name="${h#origin/}"
if [[ -z "$name" ]]; then
  for c in main master trunk develop; do
    if git rev-parse -q --verify "refs/heads/$c" >/dev/null || git rev-parse -q --verify "refs/remotes/origin/$c" >/dev/null; then name="$c"; break; fi
  done
fi
dflt=""
if [[ -n "$name" && "$name" != finish-line ]]; then
  if git remote get-url origin >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git fetch -q origin "$name" >/dev/null 2>&1 || true
  fi
  l="$(git rev-parse -q --verify "refs/heads/$name^{commit}" 2>/dev/null)"
  r="$(git rev-parse -q --verify "refs/remotes/origin/$name^{commit}" 2>/dev/null)"
  if [[ -n "$l" && -n "$r" ]]; then
    if git merge-base --is-ancestor "$l" "$r"; then dflt="$r"; else dflt="$l"; fi
  else
    dflt="${l:-$r}"
  fi
fi

created=0
if git rev-parse -q --verify refs/heads/finish-line >/dev/null; then
  [[ "$cur" == finish-line ]] || git checkout -q finish-line || refuse "could not check out finish-line"
  on_run_branch=1
else
  git checkout -q -b finish-line || refuse "could not create branch finish-line"
  created=1; on_run_branch=0
fi
old="$(git rev-parse HEAD)"
# On the run's own branch, its code changes go too: the tree starts from the default branch.
# Anywhere else the branch is the owner's, so only Finish Line's own files are removed.
base="$old"; from="$cur as it is"
if [[ $on_run_branch -eq 1 && -n "$dflt" ]]; then base="$dflt"; from="$name as it is now ($(git rev-parse --short "$dflt"))"; fi

# Finish Line's own files in that tree: .finish/, test files under a finish/ directory, and every
# spec an old ledger names.
idx="$GITDIR/finish-line-fresh.index"
rm -f "$idx"
GIT_INDEX_FILE="$idx" git read-tree "$base" || refuse "could not read the tree of $base"
{
  git ls-tree -r --name-only "$base" | grep -E '^\.finish/'
  git ls-tree -r --name-only "$base" | grep -E "$FL_PROTECTED_RE" | grep -E "$FL_TEST_PATH_RE"
  for rev in "$old" "$base"; do
    git show "$rev:.finish/ledger.json" 2>/dev/null | jq -r '.items[]?.verify.spec // empty' 2>/dev/null
  done | while IFS= read -r p; do git cat-file -e "$base:$p" 2>/dev/null && printf '%s\n' "$p"; done
} | sort -u > "$idx.paths"
GIT_INDEX_FILE="$idx" git update-index --force-remove --stdin < "$idx.paths"
tree="$(GIT_INDEX_FILE="$idx" git write-tree)" || refuse "could not build the fresh tree"
rm -f "$idx" "$idx.paths"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="finish-line-archive/$stamp"
merge=0
[[ "$base" == "$old" ]] || git merge-base --is-ancestor "$base" "$old" || merge=1

if [[ "$tree" == "$(git rev-parse "$old^{tree}")" && $merge -eq 0 ]]; then
  if [[ $created -eq 1 ]]; then git checkout -q "$cur" && git branch -q -D finish-line; fi
  commit=0
else
  parents=(-p "$old")
  [[ $merge -eq 0 ]] || parents+=(-p "$base")
  new="$(printf 'chore(finish): fresh start\n\nThe review starts over from %s, without .finish/ or Finish Line'"'"'s tests.\nThe previous run is kept at branch %s (%s).\n' \
    "$from" "$archive" "$(git rev-parse --short "$old")" | gitc commit-tree "$tree" "${parents[@]}")" || refuse "could not create the fresh-start commit"
  git branch "$archive" "$old" || refuse "could not create branch $archive"
  if ! git reset -q --keep "$new"; then
    git branch -q -D "$archive"
    refuse "could not move finish-line to the fresh-start commit"
  fi
  commit=1
fi

moved=0
if [[ -e .finish ]]; then   # only ignored files are left (evidence, logs, companion state)
  mkdir -p "$GITDIR/finish-line-archive/$stamp"
  mv .finish "$GITDIR/finish-line-archive/$stamp/.finish" || refuse "could not move .finish/ aside"
  moved=1
fi

if [[ $commit -eq 0 && $moved -eq 0 ]]; then
  say "fresh start: nothing to clear (no earlier Finish Line run in this checkout)"
  exit 0
fi
if [[ $commit -eq 1 ]]; then
  say "fresh start: finish-line is now $from, without .finish/ or Finish Line's tests ($(git diff --shortstat "$old" HEAD | sed 's/^ *//'))"
  say "  the previous run is kept: git log $archive"
fi
[[ $moved -eq 0 ]] || say "  its ignored files (evidence, logs): ${GITDIR#"$PWD"/}/finish-line-archive/$stamp/.finish"
say "  next: the review starts at Phase 0, from the docs"
