# Clean-Sweep — Phase 6 post-run housekeeping

Promotion is human-*owned* but not human-*only*: in practice users usually want the coordinator
to finish the job once the anti-inflation gate is green. So **offer** these as an explicit final
step (don't silently assume, don't refuse). When the user says go, follow this sequence.

## 1. Promote BASE → default branch

Check divergence first: `git log <default>..BASE`. If 0 commits landed on the default branch
since the fork, it's a clean fast-forward. Open a **promotion PR whose body carries a
`Closes #N` for EVERY finding closed this run** (Lane-A + any verify-first done-no-change) —
merging it to the default branch auto-closes them all in one shot (see `learnings.md` #29, #38).
Merge commit-preserving.

## 2. Verify auto-close fired

Verify the auto-close fired; deterministically `gh issue close <n>` any straggler with a
comment linking its fix PR (idempotent). The remaining open issues should be exactly your
Lane-0/OPS + Lane-B.

## 3. Reconcile stale branches

This is real cleanup value, not just deletion. List every remote branch, classify each vs the
default branch:

- **MERGED** — ancestor of the default branch → delete.
- **SUPERSEDED** — a different branch already implements the fix → verify, then delete.
- **UNMERGED** — has unique commits → **do NOT delete blindly**.

For UNMERGED, check whether the run superseded it. If it's a *real* fix the run missed,
**salvage it** — cherry-pick onto a fresh branch off the default, author-reset to maintainer,
run a build-blind review, merge — rather than delete. This pass routinely surfaces a genuine
gap the run missed (once: a residual S0 security gap plus 3 real fixes; see `learnings.md`
#42). Keep a source branch until its fix is salvaged+merged, THEN delete it. Never delete a
branch checked out in another worktree.

## 4. Fast-forward the working branch

Fast-forward the working branch to the default if it's a stale pointer. **Stash any leftover
working-tree files first** — they're recoverable, don't discard the user's uncommitted work.
