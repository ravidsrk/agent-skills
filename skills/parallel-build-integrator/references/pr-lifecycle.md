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
```

Add no "Generated with" footer or AI attribution unless the user wants it. Some GitHub tools append a footer with a session link when they create a PR. Read the description back after creating it, and update it without the footer.

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

## Review-comment sweep

Use this when review comments on merged PRs went unanswered: every finding gets an outcome, on the PR it came from.

1. **Collect** every finding from each merged PR: review threads, review bodies and check-run annotations. Give each one an id (`B<batch>-<n>`) and record its thread id and comment id.
2. **Classify each against current main**, with evidence (file:line, or a reproduction):
   - still present;
   - already fixed;
   - does not reproduce;
   - intended;
   - advisory (coupling counts and impact notes, with no defect claimed).
   Parallel read-only agents can each take a batch of PRs.
3. **Fix the still-present ones by area.** Brief one owner per area (Step 2), with the decisions already made. Each owner writes a results file: `[{id, status: fixed|deferred, commit, note}]`. A deferred item needs a plan and a reason.
4. **Integrate and gate** as usual. If another PR lands mid-sweep, resolve conflicts by keeping both sides' intent. Tell owners about shared numbering, such as migration numbers.
5. **After the merge, post the outcomes:**
   - **One comment per PR** with a table: id, file:line, finding and outcome. Advisory notes go in a collapsed `<details>`.
   - **On each open thread,** reply with the same outcome, then resolve it.
   - **Map owner SHAs to integrated SHAs** by commit subject, including SHAs cited inside notes; an owner's worktree SHA doesn't exist on GitHub after a cherry-pick.
   - **Post sequentially** from one agent, logging each PR as it's done so a rerun resumes and doesn't duplicate. GitHub's secondary limit allows about 80 content-creating requests a minute.
6. **File one tracking issue** for the deferred findings and the follow-ups owners found outside their paths.
