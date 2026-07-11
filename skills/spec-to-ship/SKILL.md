---
name: spec-to-ship
description: >-
  Turn a frozen spec/doc set into a shipped, verified product in one end-to-end autonomous run. A thin
  coordinator drives a fleet of AI coding agents through a strict PR-per-task pipeline — THINK →
  PLAN(freeze) → FOUNDATION → parallel SLICES → INTEGRATION → HARDENING → e2e TEST(with teeth) →
  ADVERSARIAL red-team → SHIP → REFLECT — with build-blind review, a second bot reviewer, a durable
  file-ledger as external brain, and the hard-won merge/wrong-base/worktree/migration/secret gotchas
  that otherwise silently break the run. Use when
  autonomously building a whole product/system from ready specs by fanning work across many coding agents
  (Orca orchestration, git worktrees, sub-agents, codex/claude terminals); coordinating parallel builders
  and reviewers with BugBot/adversarial review; verifying a build actually works (anti-inflation e2e gate,
  refuse-surface suites, drift ratchets); or when a long autonomous run stalls, mis-merges, or merges to
  the wrong base.
license: MIT
compatibility: >-
  Requires the Orca multi-agent runtime (running, orchestration experimental feature enabled) and the
  companion `orchestration` skill. Worker CLIs `codex`/`claude` on PATH; `git` + `gh`; `python3`; bash/zsh.
  Optional: `gitleaks` and a PR review bot (e.g. Cursor BugBot). The coordination layer is Orca-specific; on
  another harness only the strategy half (references/) carries over.
metadata:
  author: ravidsrk
  version: "1.0.0"
  origin: >-
    distilled from a full autonomous product build — THINK→PLAN→10-task foundation, ~20 parallel slices,
    integration, NFR hardening, and an adversarial red-team phase; ~18 real bugs caught including P0
    cross-tenant authz bypasses, a wrong-base merge, and hollow (non-durable) persistence.
---

# Spec to Ship

Coordinate a fleet of AI coding agents to turn a frozen spec/doc set into a shipped, demonstrably-working
product end-to-end — in one autonomous run, without the coordinator itself writing code. You (the coordinator) are a **thin loop-holder**: create
tasks, spawn workers, dispatch, wait, answer worker questions, sequence merges, decide what runs next. A
**durable file-ledger is your source of truth**, not your memory — so the run survives your own context
resets and mis-reports.

This skill is the distilled playbook + the gotchas that actually bite. Read `references/gotchas.md` before
your first merge — several failures are silent (a merge that reports success but didn't land, or landed on
the *wrong* branch) and will corrupt the run if you trust worker reports instead of verifying. Read
`references/verification.md` before you call the build "done" — a green unit suite is the *start* of
verification, not the end; the decisive bugs are caught by the e2e gate, the adversarial red-team, and
drift ratchets, not by per-task tests.

## When to use

- Building a non-trivial system by fanning work across many agents (parallel builders + reviewers).
- You have a coordinator harness (Orca or similar) that spawns terminals/worktrees and dispatches tasks.
- You want a PR-per-task pipeline with a real review gate (and optionally a second bot reviewer like BugBot).
- A long autonomous run is stalling, looping on review, mis-merging, or losing loop state.

If it's a single small change, don't orchestrate — just do it. Orchestration overhead only pays off across
many independent, parallelizable tasks.

## The two rules that save the run

1. **Verify, never trust.** A `worker_done` that says "merged" is a *claim*. Confirm it: `gh pr view <n>
   --json state` must read `MERGED` and the file must be on the base branch. In practice a worker *will*
   falsely report a merge (see the merge trap in gotchas). Treat a missing/malformed completion as
   NOT-done.
2. **The ledger is the brain.** Update `docs/build-progress.md` at task start, every completion, and
   before/after every merge + cleanup. A fresh coordinator with zero context must be able to resume from
   it alone. Write a full handoff block on context pressure and hand off — a clean shift-change beats a
   degraded coordinator.

## Lifecycle

`THINK → PLAN → PLAN_FROZEN → BUILDING → TESTING → ADVERSARIAL → SHIPPING → REFLECTING → DONE`. Never skip a
phase; never re-open a frozen one. Mark the current phase at the top of the ledger.

- **THINK** — one agent reads every spec doc → `requirements-index.md` (stable IDs R1…, N1… for functional
  + non-functional, out-of-scope, ambiguities-with-defaults). A second decides architecture →
  `architecture.md`. **Verify load-bearing external deps are real/installable before freezing** (we caught
  a framework whose real package name differed from the spec's — a research step, not an assumption).
- **PLAN** — decompose into a dependency-ordered task graph (`plan.md`): foundation first, then vertical
  feature slices, then integration, then the NFR hardening. Include a **traceability matrix** (every
  requirement → ≥1 task, zero orphans, machine-verified) and a **hot-file collision map**. Then a
  **fresh, spec-blind skeptic** stresses the plan and fixes real dependency-order bugs → **freeze**.
- **BUILD** — foundation serializes (dep-correct); slices parallelize. See `references/pipeline.md`.
- **TEST** — the anti-inflation gate *with teeth*: a green unit suite is **not** proof. Build a real e2e
  over the true public entry points (REST + tool surface + the real CLI over loopback) and assert actual
  persisted state (query the DB/memory/projected files for concrete rows), not exit codes. Each **negative
  control** must go RED-then-restore. This gate **surfaces hollow/deferred infra** (e.g. a store that was
  only file-backed, never persisted) — **build the missing durable piece, don't defer past the gate.**
- **ADVERSARIAL** — a red-team phase: independent, build-blind refuse-surface suites (Z1…Zn) that *attack*
  each invariant (cross-tenant authz, provenance/label smuggling, path traversal, spend/egress/TOCTOU) and
  assert refusal. A suite going P0-red is a real **finding** — fix it **in-branch** + **ratchet** it
  (red-by-revert), and **audit the whole class** (all `:tenant_id` routes, not just the one that leaked).
  Triage: P0 (fix before ship) vs backlog. See `references/verification.md`.
- **SHIP / REFLECT** — land deployable on the integration branch (merge ≠ deploy; apply is OPS). Emit
  `docs/reports/build-complete.md` + `traceability.md` (every req → task → PR, verified) +
  `go-live-runbook.md` + `backlog.md`, and **open** the promotion PR (integration → default) for human
  review — the swarm never self-merges the promotion *unprompted* or deploys. On explicit human
  authorization it may drive the promotion merge (fix-CI → verify-green → `--admin` → verify), then stop.
  **Whenever the release state changes** (promotion, a follow-up gap-closing PR), refresh the status docs in
  the same breath: rewrite live-status docs (runbook, ops-actions) to the new truth, and **banner-close**
  historical ledgers/reports with a dated pointer forward. A stale handoff doc misleads OPS worse than a
  missing one (naming the wrong release candidate, listing shipped work as "deferred").

## The PR-per-task pipeline (one task = one branch = one PR = one merge-commit)

BUILD (builder) → OPEN PR + reconcile bot review (integrator) → build-blind REVIEW (fresh reviewer) →
conflict-aware MERGE (never squash; delete branch) → WT_CLEAN. Track each task with boolean gates in the
ledger — a task advances only when the flags read true **in the file**:

```
<task> BUILT=t PR_OPEN=t BUGBOT=t REVIEWED=t MERGED=t WT_CLEAN=t [req: R#,R#] [PR#<n>]
```

**Invariants:**
- **Builder ≠ reviewer terminal.** The reviewer is a *fresh session* in the task's own worktree — build-blind
  (never saw the builder's conversation), so it actually tries to fail the work.
- **Builders never open PRs; integrators do.** A builder that self-opens a PR gets `main` as the default
  base and merges the fix to the *wrong* branch (gotcha #13). The build-blind integrator opens the PR
  against BASE, and its spec **asserts `baseRefName==<BASE>` before merging**.
- **Foundation serializes, slices parallelize.** Scaffold/data-layer/auth/seams/test-harness land first.
  Then run disjoint slices in parallel; **one in-flight task per hot file** (`package.json` etc.) —
  build in parallel, **merge serially** with rebase-union. At scale the real bottleneck is the shared
  **mount-point files** (route registry, DI wiring, approval-gate/roles, workflows index): treat each as a
  **merge chain** — build parallel, merge one-at-a-time as a union, one integrator per chain-file.
  Migrations are their own lane (pre-assign numbers; renumber-on-rebase — gotcha #14). See
  `references/pipeline.md`.
- **Commit hygiene:** author = the maintainer, no `Co-authored-by`/agent trailers, small logical commits,
  gitleaks before every push; no NUL-byte/binary source files (a recurring builder failure — gotcha #18).

Full spawn sequences, merge rules, and the bot-reconcile loop: `references/pipeline.md`. For a **bounded set
of disjoint changes** (e.g. closing a backlog), a lighter loop — parallel subagents build the new files, the
coordinator owns the shared spine (wiring/migration-numbers/barrels) and integrates + verifies — often beats
the full pipeline; see `references/pipeline.md` (Lightweight mode).
The ledger template + boolean-gate discipline: `references/ledger-template.md`.

## The gotchas that actually bite (read `references/gotchas.md`)

These are silent or expensive failures observed in a real run. The headlines:

1. **Merge trap** — a hung bot "autofix" check leaves the PR `UNSTABLE` forever; a plain `gh pr merge`
   **silently no-ops** and some workers report success anyway. Once real gates are green + the bot *review*
   concluded + findings reconciled → **merge via `--admin`**. Bake auto-`--admin`-on-merge-trap into the
   integrator spec so it doesn't hang waiting for a check that never completes.
2. **A merge isn't done at `state=MERGED`** — it's done at `state=MERGED` **AND `baseRefName==<BASE>` AND
   the change is greppable on `origin/<BASE>`.** A builder self-opening a PR gets `main` as base and merges
   the fix to the *wrong* branch (gotcha #13). Builders never open PRs; verify the fix is *on base*.
3. **Answer worker decision-gates via terminal-send** (and the CURRENT re-ask id), not only the reply
   channel — the reply often doesn't reach the worker's blocking `ask` (it re-asks; terminal-send unblocks).
4. **Sync the coordinator's local base before each new worktree wave** — `worktree --base-branch` resolves
   the *local* ref; a stale local base makes workers build on outdated code (they add shims / stack branches).
5. **Env-var parity** — adding a var to the example file but not the typed env-spec (or vice-versa) breaks
   the base suite; require both in every env-touching task spec.
6. **One owner per base fix** — don't let parallel PRs each bundle the same base-defect fix (3 tasks
   "fixed" one drift → collision). Fix it in ONE task; others drop the dup on rebase.
7. **Normalize bot-authored commits** (author→maintainer, strip trailers, never squash) and re-verify;
   **supersede incomplete autofixes** — the bot even flagged its own speculative autofix as buggy.
8. **Heartbeats mean alive, not done; a wait timeout is a checkpoint, not a failure** — never kill a
   slow-but-live worker. **Report state-changes, not heartbeats** — a wall of "still holding" reads as
   *stuck* even mid-merge (integrators auto-merge; don't race them — gotcha #16).
9. **Review-loop cap (≈3 rounds).** When a second bot keeps finding *doc-level* nits, the coordinator
   forces convergence (merge + route residual nits to backlog) rather than looping forever.
10. **Migrations stay monotonic** — pre-assign a number per migration task; renumber-on-rebase when a lower
   new number would land after a higher one already merged, or the runner skips it (gotcha #14).
11. **The harness classifier can block skip-permissions worker spawns mid-run** — that's a real human gate;
   surface it for authorization, don't retry blindly (gotcha #19).
12. **Secrets** — gitignore `.env` first; workers never receive real keys (fixtures + `.env.example` only);
   CI is fixture-only, no live spend. If keys land in the chat, flag rotation immediately.

## Quality bars worth enforcing (they paid off)

- **Encode invariants in the type system**, not just tests: e.g. "only humans can decide gates" as an
  *unrepresentable* scope — removing the guard must fail `tsc`. Adversarial negative-tests prove it.
- **Seam-fence lint**: vendor SDK imports allowed only in their one adapter file; a planted violation must
  fail CI. **Fixture-only CI**: assert no network egress, no real spend.
- **Adversarial refuse-surface suites find what green suites miss.** A dedicated red-team phase (Z-suites)
  caught 4 real security bugs — path traversal, provenance smuggling, and TWO cross-tenant authz bypasses —
  that slices, hardening, AND the e2e gate all passed over. Attack each invariant, assert refusal, audit
  the *whole class*, fix in-branch + ratchet (red-by-revert). See `references/verification.md`.
- **Negative controls with teeth + drift ratchets.** An e2e negative control that can't go red is
  decoration — prove each reddens (break the precondition, watch it fail, restore). A **drift ratchet**
  (recorded live surface vs advertised surface) catches "capability card advertises tools that 404."
  Caveat when reading their CI logs: these suites **print their planted-violation text on the GREEN path**
  (that's the point), so triage a failing run by the real `FAIL`/`Tests N failed` marker, not the scary
  lines (gotcha #22).
- **Second bot reviewer earns its cost.** In one run BugBot caught ~14 real bugs a green suite missed —
  spend-attribution bypasses, TOCTOU races, an egress-guard bypass, a cross-tenant leak, an authz
  fail-open, a migration that would lock legacy rows. Reconcile every finding; supersede weak autofixes.

## Coordinator anti-patterns

- Ending your turn (or asking the human "shall I continue?") while work remains — take the next action.
- Trusting a `worker_done` merge claim without `gh pr view` verification — including `baseRefName==<BASE>`
  and the fix actually greppable on base, not just `state=MERGED`.
- Re-planning after freeze (record new scope as backlog, don't silently re-decompose). But DO re-read the
  full task list early — the visible prefix isn't the whole scope — and let the verification layer surface
  genuinely-missing work as new tasks.
- Narrating every heartbeat ("still holding…") — it reads as *stuck*. Report state-changes: merges,
  findings, phase transitions, gates. And don't `--admin`-race an integrator that's mid-merge.
- Re-running a flaky check to slip past it instead of deflaking the root cause. A timeout-only failure
  that PASSES on a sibling run of the same commit is a flake — widen the offending test's timeout
  (subprocess/scan-in-a-loop tests especially), don't re-run and hope (gotcha #21).
- Fighting fragile per-row ledger regex — reconcile a whole authoritative state-block from git instead;
  git is truth, the ledger is its cache (gotcha #15).
- Spawning speculative/duplicate workers, or more than you can review → thrash. Smallest waves that keep
  the pipeline saturated.
- Letting the swarm *autonomously* merge the promotion PR or deploy — merge ≠ deploy. The swarm OPENS the
  BASE→default promotion for human review and merges it **only on explicit human authorization** (then
  fix-CI → verify-green → `--admin` → verify `state=MERGED`+base, like any merge). Apply/provision stays
  human/OPS, surfaced not faked.
- Building every backlog "gap" without checking it's real and appropriate — some are *phantoms* (the target
  was refactored away) or architecturally wrong (branding a value that's parsed from request input). Grep
  the current tree first; a documented **decline-with-rationale** is first-class (gotcha #23). And closing
  every *code* gap doesn't move a launch gated on live provisioning + certification + time — say so plainly.
- Grinding on in a degraded/bloated context instead of writing a handoff block and shift-changing.
