# Pipeline mechanics — spawn, dispatch, review, merge, cleanup

CLI shown is Orca `orca orchestration` / `orca worktree` / `orca terminal`. Adapt verbs to your harness;
the *shape* is the point. Parse all JSON defensively (`json.JSONDecoder().raw_decode` tolerates a stray
log line prepended to the JSON — a real cause of "wait failed exit 1" noise).

## Worker placement

- **Independent work** (a task's first build) → a NEW worktree on its own branch off BASE, a **child** of
  the coordinator (omit `--no-parent`). Record the worktree id (WT) in the ledger at spawn.
- **Dependent work** (that task's build-blind review, fix-rounds, integrator) → a FRESH TERMINAL inside
  **that task's own worktree** (target its WT id, not `active` — `active` can resolve to the coordinator
  root). A fresh terminal = a fresh build-blind session sharing the branch.

## Spawn sequence (independent build, max effort)

```
git fetch; git pull --ff-only origin <BASE>        # sync coordinator local base FIRST (gotcha #3)
orca worktree create --name <slug> --repo <selector> --base-branch <BASE> --json
orca terminal create --worktree id:<WT> --title <slug> --command '<agent-cli> <auto-flag> <max-effort-flag>' --json
orca terminal wait   --terminal <handle> --for tui-idle --timeout-ms 60000 --json   # never dispatch before idle
orca orchestration task-create --spec "<HANDOFF-TRIAD spec>" --json
orca orchestration dispatch --task <taskId> --to <handle> --inject --json
```

- `<auto-flag>`: the CLI's skip-permissions/auto mode (claude: `--dangerously-skip-permissions`). A worker
  blocked on an internal approval dialog defeats the run.
- Find the worker handle after create by listing the worktree's terminals and picking the newest whose
  title is the agent marker (e.g. `✳ Claude Code`); it retitles itself after starting a task.
- If `task-create`/`dispatch` return null ids in your JSON shape, re-query `task-list` and match by a
  unique spec prefix, then dispatch by that id.

## HANDOFF-TRIAD task spec

Every spec carries: **GOAL** (what to build), **CONTEXT** (the plan section + requirement IDs it satisfies,
the files/interfaces, prior decisions, the authoritative spec path), **EXPECTED RESULT** (concrete
done-state + acceptance command + branch to produce). A worker never guesses scope. Always include: commit
as `<maintainer>` with NO trailers; gitleaks-clean; push; send `worker_done`; and (for env-touching tasks)
the env-parity rule.

## The per-task pipeline

1. **BUILD** (builder). Real working slice (not a stub), reusing merged primitives. Add tests that FAIL
   without the implementation. build + lint + affected tests GREEN. Set `BUILT=t`. PUSH. `worker_done` with
   `{taskId, dispatchId, filesModified}`.
2. **OPEN PR + REVIEW + MERGE** (a fresh build-blind session in the task's worktree). For code tasks, fold
   the build-blind review INTO the integrator: it *verifies acceptance itself* (runs typecheck/tests, greps
   for stub/mock-only paths, confirms no secret leak, confirms the new tests are real not tautological),
   then opens the PR, reconciles the bot, and merges. If review FAILS → `worker_done` FAIL + specifics;
   coordinator dispatches a fix round to the SAME branch (≤3 rounds, then BLOCKED).
3. **BOT RECONCILE** (see gotcha #1, #6): bounded poll for the bot's review; normalize/supersede any
   autofix commits; ingest comments as VALID(fix)/FALSE-POSITIVE(dismiss-with-reason). If a required check
   hangs, use `--admin` once real gates are green + review concluded + the run's human-approved
   merge-trap grant (ledger D8) is recorded.
4. **MERGE** conflict-aware, commits preserved: check mergeability; if conflicts, `git fetch; git rebase
   origin/<BASE>`, resolve as a UNION preserving both intents, re-run gates, force-push with
   `--force-with-lease`. Then `gh pr merge <n> --merge` — add `--admin` only when the merge-trap check
   hangs AND the D8 grant is recorded (never `--squash`). Delete branch (`git push origin --delete` if the
   `--delete-branch` flag trips on the base worktree). **VERIFY `state=MERGED` + file on base.**
5. **WT_CLEAN** — after verified merge + branch deletion, remove the task's worktree
   (`orca worktree rm --worktree id:<WT>`), which tears down its child terminals. Guard: never remove the
   active, an unmerged, or a dirty worktree.

## Waves and hot files

- Run disjoint slices as a saturated parallel wave. **One in-flight task per hot file** — the classic hot
  file is `package.json` (and lockfile, shared config, shared test setup). Tasks that touch it **build in
  parallel, merge serially**: the second integrator rebases and resolves the `package.json`/lockfile as a
  union.
- Disjoint tasks (different dirs, no shared hot file) can integrate fully in parallel.
- After each merge, the newly-unblocked dependents become the next wave. Keep dependency chains ≤3–4 deep.

## Merge chains — serialize the mount-point hot files at scale

At real scale the throughput limit is not build, it's **integration on shared mount points**. Many slices
that each add a route/module/action converge on the same few files:

- a **route registry** (the `RouteModule` mount array — every HTTP slice edits it),
- shared `context.ts` / `index.ts` (DI wiring — every slice that adds a dependency),
- an **approval-gate** + **roles/scopes** file (every slice that adds a gated action),
- a **workflows index** (every slice that adds a workflow).

Treat each such file as a **merge chain**: tasks touching it build fully in parallel, but their PRs merge
**one at a time**, each rebasing onto the prior merge and resolving that file as a **union that preserves
every slice's entries**. Only **one integrator merges a given chain-file at a time** — a second concurrent
merge on it just forces a re-rebase. Disjoint-file tasks integrate in parallel around the chain. The
coordinator's job is to *sequence the chains*, not to widen them.

- The union set is **bigger than "the HTTP core."** A slice adding a gated action touches the route
  registry AND the approval-gate AND roles/scopes — three chains at once. Track the full union set per
  task, and merge the most-contended chain-file's tasks in the tightest series.
- **Migrations are their own lane.** Pre-assign a migration number per migration-touching task; renumber on
  rebase if a lower number would land after a higher one already merged (gotcha #14).

## Integrators auto-merge — the coordinator processes `worker_done`, then verifies

An integrator task's terminal state IS the merge: after its rebase + bot-reconcile + re-CI it runs the
merge itself (`--admin` only under the recorded D8 grant when the trap check hangs) and reports
`worker_done`. So the coordinator's merge step is mostly **verify, not
merge**: on each integrator `worker_done`, confirm `state=MERGED` **+ `baseRefName==<BASE>` +
file-on-base** (gotchas #1, #13), then advance the gates and clean the worktree. Reach for a
coordinator-run `--admin` merge (still under the D8 grant) only for a **confirmed straggler** (an integrator stuck on the merge-trap
past its cycle) or a verified docs/test-only PR on the critical path — and verify it the same way after
(gotcha #16). Don't race an integrator that's mid-merge.

## Scope discovery — the plan's visible prefix is not the whole scope

Re-read the **entire** frozen task list early; don't assume the tasks in front of you are all there is (a
run that tracked "10 slices" actually had 20 + integration + hardening + adversarial + OPS tail). And the
plan is **not exhaustive**: the e2e gate, drift ratchet, and adversarial suites (see `references/
verification.md`) will surface *missing* work — a durable store that was never built, an approvals-over-
HTTP path, tool-wiring that was assumed done. Each discovered gap becomes its **own dispatched task**, not
a silent patch. Expect scope to grow at the verification boundary and budget waves for it.

## Lightweight mode — bounded disjoint work → parallel subagents, not the full pipeline

Not every wave needs the full spawn/dispatch/integrate/merge machinery. When the remaining scope is a
**bounded set of DISJOINT changes** — each a new file or a small edit in its own area (e.g. closing a
backlog: three new adapters behind existing ports + a couple of hardening edits) — a lighter loop is faster
and just as safe:

- Fan the disjoint tasks out to **parallel sub-agents** (plain task agents, no worktree-per-task), each with
  an airtight spec: the exact interface to implement, the reference/template to mirror, and a hard rule to
  create ONLY its own new files.
- **The coordinator owns the shared spine** — the DI/wiring file, the barrel/index, migration *numbering*,
  and the one integration point. Forbid every subagent from touching those (parallel edits collide); you
  wire it all up once, in one place, after they finish.
- Then **integrate + verify + land yourself**: full typecheck, the hermetic suite, AND the live-service
  integration suite the subagents couldn't run (verification.md §7), review each subagent's diff
  (verify-never-trust — one *will* have a bug its own check missed), then land as ONE PR.

This is "coordinator owns the spine, subagents build the leaves." Reach for the full PR-per-task pipeline
when tasks are interdependent, touch hot mount-point files, or each needs its own build-blind review.

## Waiting

Block on `orca orchestration check --wait --types worker_done,escalation,decision_gate --timeout-ms <n>`,
looping N times for N concurrent finishers, dispatching newly-ready work after each. A timeout/`{count:0}`
is a checkpoint — re-issue. If the harness pushes worker messages to you directly, you can skip explicit
waits and just act on each message. Answer `decision_gate` per gotcha #2 — `reply --id <CURRENT>` records
the decision, terminal-send unblocks an expired `ask` — then keep
going.

## First-merge verification

Before trusting the pipeline, verify the FIRST merge landed as a true merge-commit (commits preserved),
authored by the maintainer with no trailers, branch deleted, worktree cleaned. The whole run inherits
whatever the first merge does.
