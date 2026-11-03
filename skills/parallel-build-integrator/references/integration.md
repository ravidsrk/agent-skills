# Integration

## Branch layout

```
origin/main ── integration branch (your worktree, $SCRATCH/integ) ── pushed to the PR branch
                     └── side worktree ($SCRATCH/integ-<name>) for each new hand-back
```

- The integration worktree is where the full test suite runs, and a run takes about 30 minutes.
- New hand-backs land in a side worktree created from the integration HEAD (`scripts/integrate.sh`). When its checks pass, fast-forward the integration branch to it (`git merge --ff-only <side-branch>`) and remove it.
- A side worktree needs its own dependency install. Hooks such as lefthook or husky fail without it.

## Cherry-pick order

Pick each owner's commits oldest-first (`git rev-list --reverse origin/main..<owner-branch>`). Integrate owners in dependency order: the one whose code others build on goes first. When two owners overlap, integrate the one with the larger change first and send the other back to rebase. They know their own code better than you do.

## Conflict classes

| File kind | Example | Resolution |
|---|---|---|
| Append-only index | ADR index, CONTRACTS list, data-model notes | `union.py`: keep both sides, ours then theirs |
| Keyed table | Status ledger rows `\| #42 … \|` | `merge_rows.py`: per key, take the side that changed from base; stop if both changed |
| Generated | bundles, lockfiles, codegen, OpenAPI JSON, schema exports | Take either side, then run the project's generator. Never hand-merge. |
| Code | anything else | By hand. Read both sides and the base, and keep behaviour from both. |

Configure the first two classes with `UNION_GLOBS` and `ROW_GLOBS` in `.integrator/config.sh`. `merge_loop.sh` handles them and stops on everything else.

### Keyed rows that moved

If one side moved a row out of the conflict region (to another section) and the other edited it, a naive row merge duplicates it. `merge_rows.py` exits 1 when a key appears twice in the file. Resolve it by hand:
1. Compare each side's row with the base (`git show <base>:<file> | grep '^| #42 '`).
2. Keep the side that changed.
3. Put it where the moving side placed it.

### Markers

After every resolution, and before `cherry-pick --continue`, check for leftover markers:

```bash
git grep -n -e '^<<<<<<< ' -e '^||||||| ' -e '^>>>>>>> ' -- . ':!*.lock'
```

`merge_loop.sh` refuses to continue while any remain. A committed `|||||||` line has happened before; this check exists because of it.

## Overlapping fixes

When two owners fixed the same defect, for example a missing git identity or an overflowing schema field:
- keep **one** fix, normally the one already integrated;
- tell the later owner which commit to keep, and have them drop their version during their rebase;
- credit the kept fix in the later owner's docs, if they wrote up the defect.

## After a hand-back is in

- Run the generators: env types, bundles, API exports. Then check `git status` is clean.
- Run lint, typecheck and the touched packages' tests in the side worktree, then fast-forward the integration branch.
- Keep a short list of every commit on the integration branch that isn't yet on main. It becomes the PR body.
