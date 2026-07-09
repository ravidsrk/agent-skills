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

---

## More learnings (from a large parallel run with a heavy non-convergent PR bot)

### 33. Recover a stalled worker with EITHER a re-Enter OR a fresh terminal — NEVER both
A `codex`/`claude` worker that shows `HB=None` may be (a) alive but slow to first heartbeat, or (b) truly
dead (the injected prompt never submitted). If you both re-Enter the "dead" one AND spawn a fresh terminal
for the same task, the original often wakes up too — now TWO workers build the same branch and you get
**duplicate/stacked commits**. Rule: first try re-Enter only (up to ~3×, ~2 min); only if it still never
heartbeats, recover with a fresh terminal — and do NOT keep re-Entering the old handle once you've spawned
the fresh one. (This bit twice in one run: two fix-units got built twice.)

### 34. A PR bot's Autofix can be *terminally* non-convergent — inspect late riders, don't blind-merge them
Beyond #24: with Autofix ON, even your **author-normalization force-pushes** re-trigger the bot, so the
branch can never settle on its own — 4+ rounds, each autofix commit spawning a finding in the *previous*
autofix. Two things that actually end it: **(a) disable the bot's Autofix at its dashboard** (root cause —
this is the user's lever, ask for it), or **(b) win a force-push-then-immediately-`gh pr merge` race**
(merging deletes the branch, so there's nothing left to push to). CRUCIAL: a late rider is **not always a
trivial autofix** — one was a real, *unreviewed* safety-LOGIC change (it removed a guard to re-validate
consent unconditionally). The merge-worker must READ each late rider: if it's mechanical, normalize+merge;
if it's unreviewed logic, DISCARD it (reset to the reviewed+green head) and re-land it as a separate reviewed
PR. Never merge unreviewed logic just because the bot wrote it. Confirm the merge's second parent == the
reviewed SHA afterward.

### 35. The `ask`/`decision_gate` reply channel can be flaky — reply to the CURRENT gate id + grant standing authority
A worker's blocking `ask` can time out and **re-emit as a NEW message id** before your `reply` lands,
producing a re-ask loop (you reply to the old id; it's already moved on). Fixes: the worker's heartbeat
subject usually names the id it's blocked on (`blocked on decision_gate <id>`) — reply to THAT id; and put
**"standing authorization: proceed with option X now, do not re-ask; if the reply races, keep going"** in the
reply body so the worker acts even if delivery is unreliable. Keep gate options crisp (A/B/C) so a one-word
answer resolves it.

### 36. Run the format-sweep LAST (right before the gate), not once early
Extends #18: every fix-unit that forks *before* a format-sweep merges can introduce **new** formatter drift
on the files IT touches, which an early sweep never saw. A single early format-sweep therefore leaves
residual drift that the E2E gate's whole-repo `oxfmt --check` flags on some later unit's file. Schedule the
format-sweep as the LAST fix-unit before the gate (or expect a one-file format follow-up after the gate).
Integrators should also revert a bot autofix's stray whole-repo format edits to keep each PR's diff scoped.

### 37. A test that passes in isolation but fails in the full suite is a REAL gate blocker (test pollution)
Per-PR reviews run "affected tests only" and pass; the E2E gate's **forced full-suite run** exposes
order-dependent pollution — classic cause: fake timers + `vi.waitFor` around real I/O, plus module-mock
state not reset between suites, so a sibling suite's leftover state advances time before an assertion. Fix
it **hermetically** (reset/unmock modules in `beforeEach`, `await` an explicit promise instead of
`vi.waitFor` over real I/O) WITHOUT weakening the assertion — verify the fixed test still fails when the
production fix is reverted. This is exactly the class of break the anti-inflation gate exists to catch (#14).

### 38. Validated: the promotion-PR `Closes` trick (see #29) auto-closed 16/16 — zero manual closing
On promotion to the default branch, every `Closes #N` in the promotion PR body fired. Also: builders doing
verify-first (#21) can legitimately report **done-no-change** when a prior run already fixed a finding —
include those issue numbers in the promotion `Closes` list too (they're fixed on the branch, just not by a
new commit this run).

---

## Reducing MANUAL coordinator/user intervention (the meta-lessons — these are what actually make a run smooth)

### 39. Ask the user to turn OFF the PR bot's Autofix UP FRONT — it's the #1 source of manual babysitting
The single biggest time-sink in a run is a bot whose Autofix *pushes commits*: it's non-convergent (#24, #34),
your author-normalizations re-trigger it, and one PR becomes a 4+ round fight that eventually forces the human
to toggle the dashboard mid-run anyway. Front-load it: in the "before the run" asks, request the user set the
bot to **comment-only / off** for the run's duration (re-enable after). Comment-only findings are exactly as
useful (integrators still triage + fix them) and the branch stays stable, so PRs merge on the first pass. If
you didn't ask up front and a PR is stuck looping, ask THEN — but you've already paid for the whole run.

### 40. Pre-authorize MECHANICAL fixes in the worker preambles so workers stop asking
Every `decision_gate` a worker raises is a human round-trip (made worse by #35's flaky reply channel). The
fix: bake the answer into the preamble. Integrators/merge-workers are **pre-authorized** to apply
behavior-preserving MECHANICAL fixes themselves — a bot autofix's missing test-mock stub, a mechanical lint
error, author normalization — and re-verify green, WITHOUT asking. This doesn't compromise the separate
build-blind review (mechanical ≠ logic). Reserve gates for genuine logic/design/scope calls. In one run this
turned ~6 human round-trips (each answering "yes, apply the obvious mock fix") into zero.

### 41. The run needs NO live secrets — decline any the user offers, and advise rotation
Workers operate on code + tests + a LOCAL throwaway DB. They never need production API keys/tokens. State this
up front. If the user pastes live secrets "to help", do NOT store/echo/use them; tell them the run doesn't need
them and — since they've now transited the chat — that they should ROTATE them. (Reaffirms the secret hygiene
rule stated in SKILL.md: never commit real secrets; never echo values into PR bodies or comments.)

### 42. Post-run stale-branch reconciliation is real cleanup value — and surfaces gaps the run missed
After promotion, the repo is usually littered with stale branches (fix-unit leftovers, pre-existing feature
branches with dead remotes). Reconcile them (Phase 6): classify each vs the default branch — MERGED (delete),
SUPERSEDED (a *different* branch already implements it → verify, delete), or UNMERGED (unique commits). Do NOT
blind-delete UNMERGED ones: check if the run superseded them; if one is a REAL fix the run missed, **salvage**
it (cherry-pick onto a fresh branch off default → author-reset → build-blind review → merge). This routinely
finds genuine value — in one run it surfaced a residual **S0 security gap** plus 3 real fixes the sweep had
missed. Keep a source branch until its fix is salvaged+merged, then delete. Never touch a branch checked out in
another worktree. Finally, fast-forward the stale working branch to the default (stash leftover working-tree
files first — recoverable, don't discard). Offer all of this; don't assume — but users usually want it.

---

## The sharpest anti-inflation lesson (from standing up a real live-op E2E gate)

### 43. Mocked tests can be 100% green while the real integration is 100% broken — the gate needs ≥1 LIVE call per external service
The strongest form of "green tests ≠ working product." A third-party connectors integration had **4 passing
unit tests** (mocked `fetch`) yet **every** real connection failed: the code used the wrong path-casing for the
vendor's current REST API (one casing convention where the live API had migrated to another) → an HTML 404 on
every request. The mock accepted any URL, so it asserted the code's OWN assumptions, never the third party's
contract. One live call caught it instantly — and then surfaced a *second* bug behind it (the vendor's newer
API version had added a now-required request field the code never sent).
**Rule:** for each external service the critical path touches (LLM, sandbox provisioner, connectors, memory,
payments), the anti-inflation gate should make ONE real call against a test account (behind a flag / gitignored
creds), not trust mocked tests. Mocks structurally cannot catch wrong-endpoint / wrong-payload / API-version
drift — exactly the class of bug a clean-sweep's per-PR (mocked) review waves through.

### 44. A live E2E harness is mostly a GOTCHA-DISCOVERY tool on the first run — make it self-heal, don't assume a clean box
Standing up a real local stack (web + agent + DB + mail) surfaces a long tail of environment/contract issues
that mocked suites hide. Real ones hit in one run: the migration CLI crashed on a bleeding-edge Postgres
(apply the journaled SQL directly, like prod, instead of the tool); a host service already owned the DB port
and shadowed docker (drive the port from the connection string, and **free ports before boot** — framework
dev-servers spawn child workers that survive SIGTERM → `EADDRINUSE` on re-run); the auth framework rejected
programmatic signup without a consent flag + a same-origin `Origin` header; the agent's request body shape
differed from the guess. **Bake the fixes into the harness** (free ports, apply SQL directly, redact secrets)
so re-runs are deterministic — and budget the first run for discovery, not a clean pass.

### 45. Secrets: the fix run needs none (#41), but genuine live-validation + informed owner consent is a different call
#41 holds for the clean-sweep fix run itself — it needs no live secrets. But when a DIFFERENT task genuinely
requires live creds (e.g., a live E2E validation of ops) and the user OWNS them, has been told the tradeoff,
and insists, respect the informed decision rather than refusing on a loop (which becomes obstruction): inject
into a GITIGNORED file only, redact every value from all output, never commit or echo them, and flag
`_live_`-prefixed keys once. The line is not "never touch the user's keys" — it is "never *mishandle* them":
no tracked files, no echoed values, no external exfil beyond the calls the keys exist for.

---

## Landing & greening incoming (agent-authored) PRs, and cleanup safety

### 46. CI fail-fast hides deeper red — greening the REPORTED gate ≠ a green PR
CI runs its gates in order (lint → format → test → typecheck → build) and STOPS at the first failure, so a PR
that shows "red on lint" may have much more wrong behind it that CI never reached. A generated PR reported 10
oxlint errors; fixing only those would have merged a broken tree — behind the lint wall sat **5 failing tests**
(a repository fn the new code now called was missing from the test mock), **11 typecheck errors** (the agent
wrote the UI with shadcn `<Button asChild>` conventions on a **Base UI** codebase that has no `asChild` — verify
generated code against the repo's ACTUAL library idioms, not generic ones), and **8 unformatted files**.
**Rule:** before trusting "green" on any PR you are about to land, run the FULL local gate yourself
(lint + format + typecheck + FULL test suite), never just the gate CI happened to report. Corollary: agent
tools often open the PR as a **draft** → `gh pr merge` fails `"Pull Request is still a draft"` → `gh pr ready
<n>` first.

### 47. Rebasing a later PR onto a just-merged sibling surfaces INTERACTION breakage — re-gate, and grep EVERY assertion of a changed contract
Extends #10. A clean, conflict-free rebase of PR B onto BASE-with-A does NOT mean B is still green: A's landed
changes can break B's tests through interaction. Re-run the FULL gate after every rebase / serialized merge —
never assume B's pre-rebase green holds. Concretely: a PR intentionally re-mapped a job type's bundle
(`seo_audit → marketing-ops`) and updated **2 of the 3** test files that asserted the old value; the third only
failed after rebase + full-suite. **Rule:** when a change flips a mapping / constant / contract, grep the whole
repo for the OLD value's assertions — authors (human OR agent) routinely update most-but-not-all call sites.
Second-order gotcha: fixing one lint error can EXPOSE the next (removing a redundant cast enabled TS narrowing,
which then made a downstream `String()` conversion newly-redundant) — re-lint to a fixpoint, don't stop at the
first clean pass.

### 48. Worktree cleanup: never remove the repo-ROOT (main) worktree — it owns the shared `.git` + local-only stashes
Extends #31/#42. In a repo driven by linked worktrees (Orca's model), the FIRST `git worktree list` entry is
the MAIN worktree: it holds the real `.git` that every linked worktree only *points into*, plus all `git stash`
entries (stashes live in the shared `.git` and are NEVER pushed). `git worktree remove` refuses the main
worktree, and `rm -rf`-ing it destroys every worktree — including the one you are standing in — and every stash
permanently. Before removing ANY worktree in Phase-6 cleanup, confirm: it is a *linked* (not main) worktree, its
branch is merged, its tree is clean (`git status --short` empty), and it has no unpushed stashes worth keeping.
**Even when the user says "remove all of them," surface a root-worktree / non-empty-`stash list` risk and stop —
a merged branch does not make an unpushed stash recoverable.**
