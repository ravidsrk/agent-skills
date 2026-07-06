# Clean-Sweep — hard-won operational learnings

Every item here cost real debugging time on a live autonomous run. Read before spawning workers.

## Dispatch & orchestration

### 1. `dispatch --inject` pastes but does NOT submit for claude workers
`orca orchestration dispatch --task <t> --to <h> --inject` types the prompt into the target agent's
input box but does **not** press Enter for **claude**-based terminals — the prompt sits unsent, the
worker stays idle (no heartbeat, no progress) while its siblings run. `codex` terminals auto-submit;
claude usually does not (the inject is a paste, not paste+Enter).

**Fix:** after every inject to a claude worker, wait ~8s for the paste to land, then submit with
`orca terminal send --terminal <h> --enter` (the `--enter` flag alone works; no `--text` needed).
An extra Enter to an already-submitted worker is harmless (empty submit ignored). Verify a heartbeat
within ~60s; re-Enter if none. `scripts/spawn_worker.sh` bakes this into a 3× retry loop.

### 2. Re-dispatching to the SAME handle after reset is a no-op
`task-update → ready` then `dispatch` to a handle that already had this task returns dispatch id
`null` and does nothing. To recover a worker that never heartbeated, create a **FRESH terminal** and
dispatch there — the fresh terminal creates a new dispatch context.

### 3. `check --wait` returns one message at a time, and `count:0` is a checkpoint, not a failure
- `check --wait` returns a single message; if N workers can finish together, loop N times.
- A `{count:0}` / timeout means "nothing yet", **not** "worker failed". Coding tasks routinely run
  15–60 min. Keep rolling waits unless you get `worker_done`/`escalation`, the terminal exits, or the
  user says stop.
- It also emits `_heartbeat` lines that corrupt naive JSON parsing — use `scripts/pm.py` (strips
  heartbeat lines, decodes successive JSON objects) or reconcile via the non-consuming `inbox`.

### 4. Use ONE tracked background wait — never `&` / `nohup`
Backgrounding an `orca ... check --wait` with `&` or `nohup` makes it **untracked** — you miss the
completion notification entirely. Use a single harness-tracked background invocation (the tool's own
`run_in_background`), or a foreground rolling wait. This was slipped on repeatedly; it silently
drops `worker_done` messages.

### 5. `terminal read` is blind to claude's alt-screen TUI
`orca terminal read` shows only scrollback, not the live alt-screen a claude TUI renders into. Do
not use it to judge whether a claude worker is alive or done — use the **heartbeat** (via
`dispatch-show --json` → `last_heartbeat_at`) as the liveness signal.

### 6. Dispatch inject race — worker never heartbeats
If the inject landed before the TUI was ready, the worker never starts. `spawn_worker.sh` waits for
`tui-idle` then sleeps ~20s to let the TUI settle **before** injecting. If it still never heartbeats,
recover with a fresh terminal (see #2).

## Third-party PR bot (Cursor BugBot / CodeRabbit / etc.)

### 7. Bot autofix never converges on its own — only merging stops it
The bot keeps re-reviewing and may keep auto-pushing fix commits every time the branch changes. It
will never "settle". Poll for stability (floor 3 min / cap 10 min), accept its **valid** findings,
**normalize** its auto-pushed commits (reset author → `{{MAINTAINER}}`, strip trailers, never
squash), hard-freeze the branch, and **merge fast**. Merging is the only thing that ends the loop.

### 8. Bot commits violate author/trailer hygiene by default
Bot autofix commits are authored as the bot (e.g. `cursoragent@cursor.com`) and often carry
trailers. Rebase to reset author + strip trailers **across all commits** before merge.

## Git / merge / migrations

### 9. Never squash — preserve every commit
The run's contract is commit-preserving merges (`gh pr merge --merge`, or `git merge --no-ff`).
Squashing loses the individual fix commits and is a hard violation.

### 10. Serialize hot-file collisions; rebase later findings onto merged earlier ones
Two findings editing the same router/schema/shared-config will conflict. Assign a merge order in the
ledger; after finding A merges, rebase finding B onto the new `{{BASE}}` and re-verify before its PR
merges. Parallel-merging both produces a broken tree.

### 11. DB migration number collisions
Two parallel findings both add `0031_*.sql`. The second must be **renumbered** (`0032_*.sql`) AND the
migration journal (`_journal.json` for Drizzle) updated with the matching index — otherwise the
orphan migration is **silently skipped** at `db:push` and never runs. The schema-diff check does not
catch a journaled-vs-file mismatch; the anti-inflation gate's real-DB push does.

### 12. GitHub self-approval is blocked on a shared account
Everything runs under one GitHub identity, so `gh pr review --approve` fails ("can't approve your own
PR"). Do **not** gate merge on GitHub's `reviewDecision=APPROVED`. The build-blind reviewer posts
PASS as a **comment**; the **coordinator's** confirmation of that PASS is the merge gate.
`gh pr merge --merge` succeeds regardless of review state (even when `mergeStateStatus` is UNSTABLE
due to a known-non-blocking check).

### 13. `worktree rm` sometimes drops its response but still succeeds
`orca worktree rm` may return `runtime_unavailable` while having actually removed the worktree.
Verify the directory is gone; only retry if it still exists.

## Verification

### 14. Green tests ≠ working product — the anti-inflation gate catches build-breakers reviews miss
Per-PR reviews run only *affected* tests. A branch can pass its own review and still fail a full
`typecheck`/`build` on the integrated base (classic: a value typed `number|undefined` under
`noUncheckedIndexedAccess` / strict null checks). The end-to-end gate — fresh clean install, full
build+typecheck+lint, full suite, **real DB schema push with table-count assertion**, and
**critical-path integration tests asserting real result state** — is what makes the run trustworthy.
Expect it to catch at least one real break the per-PR reviews passed.

### 15. Verify against actual result state, not exit codes
"Tests passed" can mean "the test asserted nothing meaningful". The gate must assert real outcomes:
the rollback actually prevented the orphan row, the kill-switch actually blocked the job, exactly-once
delivery actually held, the SSE stream actually emitted non-empty bytes. Reject tautological /
coverage-padding tests at review time (a real regression test FAILS if the fix is reverted).

## Tooling / environment

### 16. Pin the toolchain; a newer default can break native deps
If `.nvmrc`/`engines` pins Node 24 but the machine defaults to Node 26, native deps (e.g. `sharp`)
may have no prebuilt binary and abort `pnpm install`, blocking every script. Workers must select the
pinned version (`nvm use 24`) before any pnpm command. Pin and log it in DECISIONS.md.

### 17. Baseline is rarely zero-error — "green" means "no NEW failures"
Record pre-existing build/lint/type/test failures at baseline. Define run-green as "adds no new
failures vs. baseline"; otherwise inherited breakage blocks every PR and the run deadlocks. Give
integrators/reviewers the explicit known-non-blocking list so they don't gate on it.

### 18. A dense ledger/markdown file gets corrupted by the repo formatter
An auto-formatter (oxfmt/prettier) can mangle a dense progress-ledger's task IDs and emphasis. Add
the ledger to the formatter's ignore list (`ignorePatterns`) so `format` stays green without
destroying your external brain.

### 19. Keep the ledger on disk, commit only at the end
The ledger (`docs/clean-sweep-progress.md`) lives in the coordinator's worktree and is re-read after
every compaction (that's how it survives your context resets). Commit it to `{{BASE}}` **only** in
the final docs PR — committing mid-run races the integrator merges into origin/BASE.

## Coordinator discipline

### 20. The ledger is the source of truth, not your memory
You will be compacted mid-run. After any context reset, **re-read the ledger first** and reconstruct
state from its flags before doing anything. Never re-plan from scratch or re-fix a finding whose row
shows `MERGED`.

### 21. RESUME detection: open-issue count overstates remaining work
On a resumed run, issues fixed by a prior pass often were never *closed*. Truth = findings with **no
merged fix commit** (`git log <fork>..HEAD`). Work only the delta.

---

## Additional learnings (from a 10-fix-unit run driven to a clean E2E gate)

### 22. `gh pr merge` authors the merge commit with the GitHub ACCOUNT identity, not local git config
Branch commits stay the configured `<maintainer>`, but the **merge commit** that `gh pr merge --merge`
creates server-side carries the GitHub **account's** display name/email (which may differ from
`git config user.email`). This is **unforceable** without doing a local `git merge --no-ff` + push
instead of `gh pr merge`. Treat the account identity as the accepted maintainer identity — it matches
every prior server-side merge and is the same person. Do NOT try to "fix" merge-commit authorship;
only branch-commit author/trailer hygiene is enforceable.

### 23. Orca worktree IDs are composite `uuid::path` — use a `path:` terminal selector
`orca worktree create` returns an id like `6607a323-...::/abs/path`, and `orca worktree list` shows the
same composite. `orca terminal create --worktree id:<uuid>` fails with `selector_not_found`. Use
`--worktree "path:/abs/path"` (unambiguous) or the full composite id. `spawn_worker.sh` now takes a raw
selector; pass `path:<worktree-path>`.

### 24. BugBot pushes autofix commits AFTER the reviewer's PASS, not just during integration
The integrator normalizes the bot's first autofix, but BugBot keeps re-reviewing the *normalized* branch
and pushes MORE `Cursor Agent`-authored commits — landing **after** the build-blind review. So the merge
worker MUST, right before merging: `git fetch` + list every commit author (`git log BASE..HEAD
--format='%h %an <%ae>'`), normalize any late `cursoragent` commits (author+committer reset, no squash,
tree unchanged), then poll BugBot to a **terminal state** (COMPLETED/SUCCESS with no new commit) before
`gh pr merge`. Seen 1–3 late commits per PR. Corollary: a coordinator-merge shortcut is only safe after
that freeze-check shows zero bot commits AND zero trailers; otherwise dispatch a merge worker.

### 25. Reviewer should verify author/trailer hygiene of bot commits, not just the code
On one PR the reviewer PASSed the code but flagged a `Cursor Agent`-authored commit for normalization —
that catch is what routed it to a merge worker instead of a clean coordinator-merge. Keep "any bot-pushed
change authored maintainer/no-trailers?" in the reviewer checklist; the reviewer is the last read before
the merge gate.

### 26. Coordinator-merge from the head-branch worktree leaves the remote ref undeleted
`gh pr merge --merge --delete-branch` run while the head branch is checked out in its own worktree fails
the LOCAL delete ("cannot delete branch used by worktree") — the server merge still succeeds but the
**remote** ref is left behind. Verify with `git ls-remote --heads origin <branch>` and
`gh api -X DELETE repos/<repo>/git/refs/heads/<branch>`. (Generalizes the sibling-worktree/BASE case.)

### 27. E2E gate: verify the "known non-blocking" build failure is *still* env-only, and mind gitignored evidence
A build task that fails only on missing env vars must be **re-proven env-only each run** (the env-schema
files byte-identical to the default branch; typecheck passes) so a real type/code break can't hide behind
it. Also: an evidence/QA-docs directory may be gitignored — a docs commit then needs `git add -f`, or a
plain `git add` silently commits nothing.

### 28. Not every PR triggers the bot — don't block on it
BugBot ran on ~5/10 PRs and skipped the rest (bounded poll hit the cap with zero activity). "Bot did-not-run"
is a valid terminal state; log it and proceed. Do not extend the poll indefinitely waiting for a bot that
isn't coming.

### 29. Close the issues via the PROMOTION PR body, not the per-fix-unit PRs (the fix for #21)
Per-finding PRs merge into the integration BASE (a NON-default branch), so their `Closes #N` keywords never
auto-close — GitHub only auto-closes on merge to the **default** branch. This is exactly the "fixed-but-not-
closed" trap in #21. The clean fix: put EVERY `Closes #N` for the whole run in the **promotion PR**
(BASE → default-branch) body — that PR merges into the default branch, so all issues auto-close in one shot
on promotion. Keep the per-fix-unit `Closes` too (documents intent, harmless), but don't rely on them. If
auto-close lags or you want certainty, also `gh issue close <n> --comment "Fixed by #<fixPR>, landed via
promotion #<promoPR>"` (idempotent even if auto-close already fired).

### 30. Group a tightly-coupled finding cluster into a few coherent fix-units, not one-PR-per-finding
When N findings live in the same 3–4 hot files (e.g. one authz subsystem), N competing PRs just conflict.
Group them by clean file-boundary into a small number of coherent, **serialized** fix-units — e.g. 6
findings in one subsystem → 2 fix-units split on a package boundary (shared primitives package → the
consumer that uses them), the second rebased onto the merged first. One-PR-per-finding is the default only
for INDEPENDENT findings; coupled ones get grouped. Record the grouping + serialize order in the ledger.
(Extends #10.)

### 31. `orca worktree rm` also tears down that worktree's terminals — WT_CLEAN is terminal-cleanup
Removing a fix-unit's worktree kills the builder/integrator/reviewer/merge terminals inside it. So at run
end there are usually **no stray worker terminals** to kill — the per-finding WT_CLEAN already did it. Do
NOT hunt-and-kill terminals in OTHER worktrees/projects; they aren't yours.

### 32. Drive N parallel pipelines from ONE `check --wait` loop + the ledger as the state machine
For a wave of independent fix-units, keep a **single** tracked `check --wait`; on each `worker_done`, read
the subject to see which fix-unit + stage finished, advance THAT unit to its next stage, update its ledger
row, re-open the wait. A parametrized **stage helper** (int/rev/merge briefs generated from params) removes
per-dispatch boilerplate across dozens of stages. Always reconcile via non-consuming `inbox` with a
**case-insensitive** subject match (worker subjects are usually upper-cased, e.g. `FU-07` not `fu-07`) so a lost/duplicated wait output
never drops a completion. Coordinator-merge the clean units (freeze-check shows no bot commits, no conflict);
dispatch a merge worker only when there's bot churn or a conflict (see #24).
