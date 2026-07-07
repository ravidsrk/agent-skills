# Gotchas — silent and expensive failures observed in real runs

Each entry: the symptom, the root cause, the fix, and the rule to carry forward. These are the failures
that corrupt an autonomous run if you don't know them in advance.

## 1. The merge trap — a "merged" report that didn't merge (CRITICAL)

**Symptom.** A worker sends `worker_done: "MERGED PR#19 sha 0f9d1c7"`, but `gh pr view 19` shows
`state=OPEN, mergeStateStatus=UNSTABLE`. The claimed sha isn't on the base branch. Foundation count is
wrong; downstream tasks build on a base missing the "merged" work.

**Root cause.** A second-reviewer bot (Cursor BugBot) posts two checks: a **review** (`Cursor Bugbot` →
`NEUTRAL`, completes) and an **autofix** (`Cursor Bugbot Autofix` → `IN_PROGRESS`, *never completes*). The
hung autofix keeps `mergeStateStatus=UNSTABLE`. A plain `gh pr merge <n> --merge` refuses to merge an
UNSTABLE PR and **silently no-ops** (exit is masked if piped) — and the worker's "merged" logic reports
success anyway.

**Fix.** Once (a) all *real* CI gates are `SUCCESS`, (b) the bot **review** check has concluded
(`NEUTRAL`/`SUCCESS`), and (c) all findings are reconciled → **merge with `--admin`** to bypass only the
hung non-required check: `gh pr merge <n> --repo <r> --merge --admin`. Then **verify**:
`gh pr view <n> --json state` == `MERGED` AND `git cat-file -e origin/<base>:<a-real-file-from-this-PR>`.

**Rule.** VERIFY EVERY MERGE. Never advance a task's `MERGED=t` on a worker's word. Bake `--admin` +
verify into every integrator task spec.

**Polling addendum.** When you wait for a PR to go green, wait on the REAL gates **by name** and **exclude
the perpetual bot check** from your condition. "All checks green" is unreachable while it hangs, and
`gh pr checks` itself **exits non-zero** (pending) the entire time — so a poll loop's final `gh pr checks`
"fails" purely because of the hung check, not a real failure. Key the merge decision off the parsed
per-check state of the required gates, not the aggregate exit code or `mergeStateStatus` (which sits at
`UNSTABLE` the whole time):
`gh pr checks <n> --json name,state,bucket` → merge once every check whose `name` ≠ the bot is terminal + green.

## 2. Worker decision-gates: use terminal-send, not the reply channel

**Symptom.** A worker `ask`s a blocking question (decision_gate). You answer via
`orca orchestration reply --id <msg>`. The worker re-emits the *same* question minutes later (observed 3×).

**Root cause.** The reply doesn't reach the worker's blocking `ask` loop in this environment (it polls, or
the id binding is off).

**Fix.** Deliver the decision straight into the worker's terminal:
`orca terminal send --terminal <handle> --text "DECISION = <option> ... proceed now, do not ask again" --enter`.
This unblocked every gate. Keep the reply as a log echo if you like, but don't rely on it.

**Rule.** Answer worker gates via terminal-send. Make decisions crisp and final ("do not ask again").

## 3. Worktree base is the LOCAL ref — sync before each wave

**Symptom.** A task built against a base missing an already-merged dependency, so the worker added "shim"
files duplicating merged primitives, or fast-forwarded its branch onto a peer's branch ("stacked").

**Root cause.** `orca worktree create --base-branch <B>` resolves `<B>` to the **local** branch ref. If you
merged work to the *remote* base but never pulled it into the coordinator's local checkout, new worktrees
fork from the stale local tip.

**Fix.** Before every new worktree wave, sync the coordinator's local base:
`git stash -u; git pull --ff-only origin <base>; git stash pop`. Confirm the expected merged dirs exist.

**Rule.** Fresh-sync local base before spawning a wave. Verify the just-merged files are present locally.

## 4. Env-var parity breaks the base suite

**Symptom.** A surface-parity test (`.env.example` ⇄ typed `ENV_SPEC`) goes red on the base after a task
added a var to one side only. Every later task's `npm test` now fails on a defect it didn't cause.

**Fix / Rule.** Any task that adds an env var MUST update BOTH `.env.example` AND the typed env spec in the
SAME commit. Put this sentence in every env-touching task spec. When it slips, fix-forward in the PR that
surfaces it (smallest change), not a separate task.

## 5. Don't let parallel PRs each bundle the same base-defect fix

**Symptom.** A base defect (the env-parity break above) was independently "fixed" by three in-flight
tasks — one directed, one told not to, one unprompted — guaranteeing a merge conflict on the shared files.

**Fix.** Fix a discovered base defect in exactly ONE place: either a dedicated tiny task, or the single PR
you explicitly direct to fix-forward. Tell every other in-flight integrator to **drop the dup on rebase**
(take base's version), keeping their diff to their own module.

**Rule.** One owner per base fix. Others resolve the conflict by dropping their redundant copy.

## 6. Normalize + supersede bot-authored commits

**Symptom.** A second-reviewer bot auto-pushes fix commits authored by the bot, sometimes squashing, and
occasionally the autofix is wrong or incomplete (the bot even flagged its own pagination autofix as buggy).

**Fix.** For every bot-pushed commit: rebase to reset author → maintainer, strip all trailers, never
squash (commits stay preserved), re-run gates. If an autofix is wrong/incomplete, **supersede** it with a
maintainer-authored fix + a regression test, or revert it and record why. Re-run gitleaks on the bot diff.

**Rule.** The internal build-blind reviewer is the final gate. The merged branch must satisfy BOTH the
reviewer AND all bot comments resolved AND every commit maintainer-authored, no trailers, green.

## 7. Heartbeats mean alive, not done; timeouts are checkpoints

**Symptom.** A worker sends heartbeats for many minutes without completing; a `check --wait` returns
`{count:0}`/times out.

**Rule.** Do NOT kill/restart a live-but-slow worker. Real coding tasks run 15–60 min. Re-issue rolling
waits. A worker fails only if its terminal exits/disappears or the harness circuit-breaks after 3
consecutive dispatch failures — then reassign, don't stop. Note: some harnesses surface worker messages to
the coordinator directly, making a busy-wait loop unnecessary — act on messages as they arrive.

## 8. Review-loop cap — force convergence on doc-level nit-storms

**Symptom.** On a docs/plan PR, the second bot kept finding new minor consistency nits each round; the
integrator kept fixing and re-polling past the round cap, never merging.

**Fix.** Cap at ~3 review rounds. When findings are valid-but-minor and the artifact is already reviewed,
the coordinator directs: "converge now — fix the current item, then merge; route residual nits to
`backlog.md`; do not start another round." Deliver via terminal-send. Real correctness findings still get
fixed; doc-polish loops don't block the pipeline.

## 9. Secrets hygiene

- Add `.env` (and `.env.*`, keeping `!.env.example`) to `.gitignore` **before** writing any `.env`.
- Workers **never receive real keys** — they build against `.env.example` (names only) + fixtures. CI is
  fixture-only: assert no network egress, no real spend. Real keys are OPS/runtime, injected out-of-band.
- Multi-worktree caveat: gitignored `.env` does NOT propagate to worker worktrees (separate checkouts) —
  which is *good*; secrets stay put and workers don't need them.
- If a human pastes live keys into the chat, that transcript is a leak: flag rotation immediately, store
  them only in a gitignored local `.env`, and never echo them into a committed file or a worker prompt.
- Run gitleaks on staged changes before every commit; `gitleaks git`/diff-scan avoids an Orca-worktree
  false-positive where `gitleaks dir .` scans the parent repo via the `.git` pointer.

## 10. Builder CLI unresponsive → fall back, preserve the invariant

**Symptom.** The intended builder CLI (e.g. codex) never reaches tui-idle / emits no output in the env.

**Fix.** Fall back to a fresh session of the working CLI (e.g. claude). Record the swap. The only hard
invariant is **builder ≠ reviewer terminal** and the reviewer never saw the builder's session — a fresh
same-model session satisfies it; you lose cross-model diversity, which is secondary.

## 11. Branch delete trips on a checked-out base worktree

**Symptom.** `gh pr merge --delete-branch` errors when the base branch is checked out in another worktree
(the merge still lands).

**Fix.** Delete the remote branch explicitly: `git push origin --delete <branch>` (or via the API). Verify
the merge landed regardless.

## 12. Coordinator git-state divergence

**Symptom.** You commit the ledger locally to the base branch, but a worker's merge advanced the *remote*
base meanwhile → your `git push` is rejected (non-ff) and `pull --ff-only` aborts (diverged).

**Fix.** `git fetch; git rebase origin/<base>; git push`. Keep coordinator ledger commits rebasing onto
the remote base. Better: pull/rebase right before each ledger commit.

## 13. WRONG-BASE MERGE — the fix merged, but to the wrong branch (CRITICAL)

**Symptom.** A P0 fix shows `state=MERGED`, yet a `verify-never-trust` grep of the file on your integration
BASE finds **zero** trace of the change — the leak the fix was supposed to close is still open on BASE.

**Root cause.** A **builder self-opened a PR** and `gh` defaulted its base to the repo's **default branch**
(`main`), not your integration branch. It merged cleanly — to `main` — leaving the fix OFF the integration
branch entirely. `state=MERGED` was true; it just merged the wrong place.

**Fix.** Recover by cherry-picking the single commit onto a fresh branch off the CORRECT base, re-verify,
open a PR against BASE, merge, and log the stray merge-to-`main` as an OPS cleanup item:
`git checkout -b <task>-redo origin/<BASE>; git cherry-pick <sha>; …open PR --base <BASE>…`.

**Rule.** **Builders never open PRs** — only build-blind integrators do, and the integrator spec must
**assert `baseRefName == <BASE>` before merging** (`gh pr view <n> --json baseRefName`). And extend the
merge-verify (gotcha #1): a merge isn't done at `state=MERGED` — it's done at `state=MERGED` **AND**
`baseRefName==<BASE>` **AND** the actual change is greppable on `origin/<BASE>`. Verify the *fix is on
base*, not merely that *a* merge happened.

## 14. Migration-number collision → renumber on rebase

**Symptom.** Two parallel tasks each pick the "next" migration number off a stale base. Task H4 wrote
`0022_*` when `0021` was highest; meanwhile H2's `0023_*` merged first. Now H4's `0022` sorts *below* an
already-applied `0023` and the runner may **skip it** (it only applies numbers above the last-applied).

**Fix.** Pre-assign a **migration lane** (a reserved number) to each migration-touching task at plan time.
On rebase, the second-to-merge **renumbers to the next free number above the highest already on BASE**
(`0022 → 0024`). The integrator does the renumber during conflict resolution; re-run the migration test.

**Rule.** Migrations must stay strictly monotonic on BASE. Pre-assign lanes; renumber-on-rebase when a
lower new number would land after a higher one already merged. Sequential-with-no-gaps beats
gaps-with-out-of-order.

## 15. Ledger regex-surgery silently no-matches; ledger commits cause integrator churn

**Symptom A.** Your in-place `sed`/regex edits to per-row ledger cells stop matching after the table shape
changed (a wave added an extra column) — rows silently stay `DISPATCHED` while git reality is `MERGED`.
The coordinator's "brain" drifts from the truth it's supposed to hold.

**Symptom B.** During a merge cascade, every coordinator ledger commit advances BASE, forcing every
in-flight integrator to rebase + re-run CI — self-inflicted churn that slows the whole wave.

**Fix.** Don't fight fragile per-row regex. Maintain an authoritative
`<!-- RECONCILED-STATE-START -->…<!-- RECONCILED-STATE-END -->` block: a hand-written current-state summary
reconciled against **git as the source of truth** (grep the merges, don't trust stale cells). And **batch
ledger commits** during a cascade — commit once when the wave settles, not after every micro-update.

**Rule.** Git is truth; the ledger is a cache of it. Reconcile the cache from git, in a block you rewrite
wholesale, not via per-cell regex. Don't churn BASE with bookkeeping commits mid-cascade.

## 16. Integrators auto-merge — don't race them; report state-changes, not heartbeats

**Symptom A.** The coordinator, impatient at the merge-trap, `--admin`-merges a PR an integrator was
*already* finishing → "already in progress"/"already merged" errors, wasted rebases.

**Symptom B.** The user asks "are we stuck?" during a *healthy, fast-merging* phase — because the
coordinator narrated a "holding…" line on every heartbeat, drowning the real signal. (In fact 4 of 5 tasks
had merged in the background.)

**Fix.** Integrators DO auto-merge after their rebase + re-CI — just slower than you poll. Give the
integrator its cycle; **self-merge only a *confirmed* straggler** (verify no integrator is mid-merge
first). Narrate **STATE CHANGES** — merges, findings, phase transitions, decision gates — **not liveness
pings**. A wall of "still holding" reads as stuck even when the pipeline is flowing.

**Rule.** Report on what *changed*, not that you're alive. Let integrators finish before you reach for
`--admin`. (Coordinator self-merge is still a valid *bounded* unblock for a verified green straggler or a
docs/test-only PR on the critical path — but verify `state=MERGED` + base + file-on-base after, same as
any merge.)

## 17. Decision-gate re-ask — answer the CURRENT id on BOTH channels

**Symptom.** (Extends gotcha #2.) A worker re-emits the same `decision_gate` with a **new msg id** because
your reply never reached its blocking `ask`. Answering the *old* id does nothing.

**Fix.** Answer the **current** msg id, and deliver on **both** channels at once: `orca orchestration reply
--id <current>` **and** `orca terminal send --terminal <handle> --text "DECISION = … proceed now, do not
ask again" --enter`. Phrase it as final.

**Rule.** Always answer the latest re-ask id, via terminal-send AND reply, crisp and final.

## 18. NUL-byte / binary source files (recurring builder failure)

**Symptom.** A builder writes a source file containing raw `U+0000` bytes; git treats it as **binary**, so
it's unreviewable in diffs and can break tooling. Observed repeatedly across independent workers
(store/event-store files were the recurring victims).

**Fix.** The integrator detects (`git grep -P '\x00'` / `file` reports "data") and normalizes to proper
`\0` string escapes before merge. Add "no NUL bytes in source; diffs must be text" to the builder spec.

**Rule.** Screen merged files for NUL bytes; it's a recurring builder failure, not a one-off.

## 19. The harness classifier can block worker spawns mid-run

**Symptom.** Spawning workers with the skip-permissions/auto flag (`claude --dangerously-skip-permissions`)
is blocked mid-run by an auto-mode safety classifier (e.g. "Create Unsafe Agents").

**Fix.** This is a genuine human gate — surface it (don't try to route around it). The user authorizes the
autonomous-worker spawn (a permission rule, or approving the specific action), then the spawn retries and
succeeds. Log the authorization in DECISIONS.md.

**Rule.** Worker spawns in auto/skip-permissions mode may need explicit user authorization from the
harness; treat a classifier block as a real gate to surface, not a failure to retry blindly.

## 20. Stale coordinator brief vs. the integrator's on-the-ground finding

**Symptom.** Your collision map says "task S12 touches `auth-middleware.ts`," so you serialize on it — but
S12 never touched that file; the real overlap was a `gateStore` default two tasks both added.

**Fix.** When a build-blind integrator reports the *actual* file overlap it found, **trust the integrator
over your stale brief**. For "both tasks added X" overlaps, the second integrator **reconciles to one
coherent mechanism** (dedup), it does not merge two competing copies.

**Rule.** The collision map is a hypothesis; the integrator's diff is the fact. Update the map from what
integrators actually find, and dedup duplicated mechanisms down to one.

## 21. Subprocess-heavy / adversarial tests flake on the default test timeout — deflake, don't re-run

**Symptom.** A promotion/integration PR's `build gates` check FAILS, but a *parallel* run of the exact same
check on the exact same commit **PASSES** — and the failure is `Test timed out in 5000ms`, not an
assertion. The offender is an adversarial/scan test that spawns many subprocesses in a loop (observed:
`gitleaks dir` over 9 content dirs, sequentially) under the runner's default per-test timeout.

**Root cause.** Each subprocess is fast locally (~950ms total) but the loop's wall-time blows the default
timeout on a loaded/slow CI runner. Non-deterministic → one run passes, the sibling flakes.

**Fix.** Give the subprocess-loop test an explicit generous timeout (`it(name, () => {…}, 120_000)`). The
assertion is unchanged — only the timeout widens — so the invariant is fully preserved. Do NOT just hit
"re-run" and hope: re-running masks the flake and lets it block the *next* promotion too.

**Rule.** A timeout-only failure that passes on a sibling run is a **flake, not a finding** — fix the root
cause (widen the offending test's timeout), don't re-run. Subprocess/scan-in-a-loop tests need explicit,
generous timeouts from the start.

## 22. Negative-control suites print alarming text on the GREEN path — read the FAIL marker, not the noise

**Symptom.** A failing CI log is full of scary lines — `X imports "@vendor" — allowed only in …`,
`schema-drift: generated files are STALE … body: number`, `seam-fence violations: probe imports "@…"`. It
reads like several failures. In fact **every one of those is inside a test that PASSED (✓)**.

**Root cause.** Fence/drift/refuse-surface suites *plant a violation on purpose* and assert the detector
reddens on it — so they legitimately emit the violation text on their happy path. The single real failure
was elsewhere (a lone `FAIL … Test timed out`).

**Fix.** Triage a failing log by the actual failure markers — the `FAIL <file>` block, a `✖`/`×` on a
*failing* test, the `Failed Tests N` / `Tests N failed` summary, and the job's final `##[error]` — not by
grepping for alarming words. Confirm which test id owns the failure before "fixing" anything.

**Rule.** Planted-violation output ≠ a failure. Identify the real failing test by its FAIL marker; don't
chase the negative-control fixtures' intentional noise (a whole class of them is by design — see
`references/verification.md`).
