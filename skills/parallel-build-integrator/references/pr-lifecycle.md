# PR lifecycle

## PR body template

```markdown
## What

<One line: which owners' work, on which main SHA.>

### <Area 1> (<epic/issue ids>)
- **<Result first>.** <what was built or measured, with numbers>
- <Fixes the work found on the way, each one line>

### <Area 2> ...

## Checks

- `<lint>` (<N> files) and `<typecheck>` (<n>/<n>) are clean.
- <Drift: API spec, migrations, pinned versions: no change>.
- Full `<test>` on a fresh database: <passed> passed, <failed> failed, each classified: <names and why>.
- Secret scan: <no matches | only placeholders: …>.

## Issues

Closes #A, closes #B.

Refs #C: <what's left, and who's on it>.

Left for live or outside resources, tracked in #<tracker>:
- #A: <the live check, and the resource it needs>.

<attribution footer>
```

Write `Closes` lines at PR creation. Editing them after the merge closes nothing.

## Shepherding

- **Subscribe to the PR's events** (CI, reviews, merge), and keep one safety-net check-in about 50 minutes out. Reset it on every event, and delete it when the PR merges.
- **Red CI:**
  1. Reproduce it locally.
  2. If main is also red, or the failure is outside the diff and reproduces on one re-run, it isn't this PR's. Port the fix in anyway, because waiting leaves the PR red.
  3. Otherwise root-cause it, fix it, and show the failing check passing before you push.
- **Review bots:**
  - Treat each finding as a claim, and trace a realistic path to the failure.
  - Real: reproduce it, fix it with a test, push, and say what changed.
  - Not real: explain why in **one** PR comment covering every declined finding, and resolve those threads.
  - Coupling counts and style labels are advisory: answer once, resolve, and don't push for them.
- **Before every push, read the PR's state.** If it's merged, the push belongs in a follow-up PR from a branch based on the merged commit. If the branch already holds only the new commits on top of a merged SHA, open the follow-up PR from it as is; no rebase or force-push is needed.

## After merge

```bash
git fetch origin main
for c in <your SHAs>; do git merge-base --is-ancestor "$c" origin/main || echo "NOT MERGED: $c"; done
```

1. **Closed issues:** comment on each with what landed and where its remaining live items are tracked.
2. **Unmerged commits:** open a follow-up PR for anything flagged `NOT MERGED`.
3. **Epics:** list each epic's sub-issues and close it once all are closed, with a short comment.
4. **Main CI:** check the run on the merge commit. A PR merged before its own CI finished has its first full run here.
5. **Reset the integration branch:** `git checkout -B <integ> origin/main`, then push as a fast-forward. Fast-forward the main checkout too.
6. **Trackers:** tick the checkboxes the PR satisfied.
7. **Check-ins:** delete stale ones (PR safety nets, "check main CI" reminders) once they're resolved.
