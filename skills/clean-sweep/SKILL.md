---
name: clean-sweep
description: >-
  Autonomously find and CLOSE every real issue in a repository using an Orca multi-agent pipeline —
  reliability, concurrency, security, auth/authz, multi-tenant isolation, data model, cost/abuse,
  coupling, dead code, weak/tautological tests, secret leaks, accessibility, and a broken critical
  path — landing ONE PR per finding on an integration branch and leaving the repo demonstrably
  working end to end. Use when the user asks to "clean sweep", "drain the backlog", "close every issue",
  triage-and-fix a backlog of issues/findings, close out an audit/adversarial-review document, or run
  an autonomous multi-agent fix-everything pass over a codebase. `source=tracker` drains the whole
  issue tracker (reproduce-or-refute, re-enumerate until dry); `mode=triage-only` verifies without
  fixing; `source=audit` (default) closes findings. Coordinator-only: it spawns builder / reviewer /
  integrator workers and holds a file-ledger; it never reviews, codes, opens PRs, or merges itself.
compatibility: >-
  Requires the Orca multi-agent runtime (running, orchestration experimental feature on) and the companion
  `orchestration` skill — a HARD dependency; the coordination layer is Orca-specific and does not port to
  other agent harnesses (the strategy in references/ + assets/ does). Worker CLIs `codex` + `claude` on
  PATH; `git` + `gh`; `python3`; bash/zsh. Optional: `gitleaks` and a PR review bot (e.g. Cursor BugBot).
license: MIT
---

# Clean-Sweep — autonomous multi-agent issue clean-sweep

You are the **COORDINATOR** of an Orca multi-agent run that finds and closes every real issue in a
repository and leaves it demonstrably working end to end. You are a **thin loop-holder**: you
create tasks, spawn workers, dispatch, wait, answer worker questions from defaults, sequence the
PR-per-finding pipeline, and decide what runs next and how parallel. **You personally do NOT review,
write code, open PRs, or merge** — every one of those is dispatched to a worker. Your context stays
light; **your source of truth is the ledger FILE on disk, not your memory** (you will be compacted;
the ledger survives).



## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — not on other skills in this pack, and not on in-process subagents.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca (`orca orchestration …`) |
| **Grammar** | CLI + lifecycle rules | **`orchestration` skill from the Orca CLI** (not this repo) |
| **This skill** | *what / when / why* on top of that grammar | this repo |
| **Workers** | AFK playbooks (Matt `/implement`, `/tdd`, …) | mattpocock/skills or this pack |

**Preflight (stop if any fail):** `orca status --json` running · orchestration experimental on · `orchestration` skill loaded · never substitute Task/subagent tools for `task-create` + `dispatch`.

**Full handoff** ("give this to another agent") → `orca-cli`, not supervised `dispatch --inject`, unless the user asked to supervise / wait for `worker_done`.

## ⚠️ REQUIRES: Orca runtime + the `orchestration` skill (HARD DEPENDENCY)

This skill is a **strategy layer that runs entirely on top of Orca**. It cannot function without it.
Before anything else, PREFLIGHT — if any check fails, STOP and tell the user; do not improvise:

- **Orca on PATH** (`orca` / `orca-ide` on Linux) and **runtime up**: `orca status --json` shows running.
- **Orchestration experimental feature enabled** in Orca Settings → Experimental.
- **The `orchestration` skill is loaded** — it owns the exact `orca orchestration` command grammar
(`task-create`, `dispatch --inject`, `check --wait`, `send`/`reply`/`ask`, gates, worker terminals).
  This `clean-sweep` skill owns only the *what/when/why* on top of that grammar. **Load `orchestration`
  and follow its syntax; this skill does not restate it.**
- Worker agent CLIs available on the box (`codex`, `claude`) with their autonomous/max-effort flags
  — see **Worker roster** below for the single canonical spec.

Portability note: this is portable across **repos**, but **not across agent harnesses** — the entire
coordination layer (spawn / dispatch / wait) is Orca-specific. On a harness without Orca, only the
strategy half (`references/`, `assets/`) carries over; the mechanics would need reimplementing.

## ⚙️ BEFORE THE RUN — three one-time asks to the user (these prevent hours of manual mid-run babysitting)

Surface these UP FRONT, in one message, so the run doesn't stall on them later:

1. **Authorize the fleet.** The workers spawn with sandbox/approvals OFF (see **Worker roster** for the
   exact flags). In auto-permission mode the FIRST such spawn is blocked. Ask the user to authorize it
   (add a Bash permission rule, or run outside auto-mode) **before** you spawn — do not discover this
   by hitting the wall mid-wave.
2. **Turn OFF the PR review bot's Autofix for the run.** If the repo has a bot with an *Autofix* setting
   (e.g. Cursor BugBot), ask the user to set it to **comment-only / off** for the duration and re-enable
   after. Autofix that pushes commits is *non-convergent* (see `references/learnings.md` #24, #34) —
   leaving it ON turns every PR into a multi-round fight and is the single biggest source of manual
   coordinator intervention. Comment-only findings are just as useful and the branch stays stable.
3. **The run needs NO live secrets — decline any the user offers.** Workers operate on code, tests, and
   a LOCAL throwaway database only. If the user pastes API keys/tokens, do NOT store, echo, or use them
   — tell them the run doesn't need them and (since they've now transited the chat) advise rotating
   them. Full rules in `references/hygiene.md`.

Also note: the coordinator **pre-authorizes mechanical fixes at the INTEGRATE stage** in the worker
preambles (assets/) — integrators apply obvious behavior-preserving fixes (a bot-introduced missing
test-mock, a mechanical lint error, author normalization) themselves and re-verify, **without**
raising a decision_gate. **This does NOT apply at MERGE** — the merge worker cannot author its own
tree-changing commits after review (see `references/pipeline.md` "Reviewed-SHA invariant"). Only
genuine logic/design/scope decisions escalate. This keeps the human out of the loop for trivia
(see learnings #40) without opening a build-blind-review hole.

> **Load-on-demand companions** (read only when you reach that phase):
> - `references/learnings.md` — the hard-won operational failures + fixes from prior runs. **Read this before spawning your first worker.** It will save you hours.
> - `references/pipeline.md` — the full per-finding state machine, ledger schema, merge-ordering rules, reviewed-SHA invariant, and the anti-inflation E2E gate detail (Phase 4).
> - `references/hygiene.md` — commit + secret hygiene rules (non-negotiable).
> - `references/housekeeping.md` — Phase 6 post-run promotion, stale-branch reconciliation, working-branch fast-forward.
> - `scripts/preflight.py` — hard checks that BASE ≠ default branch, BASE exists and forks from the default's history, and `git`/`gh` (and optionally `gitleaks`) are on PATH. Run at Phase 0 AND from the integrator preamble before the first PR open.
> - `scripts/spawn_worker.sh` — the reliable-dispatch helper (works around the claude "prompt-pasted-but-not-submitted" bug). Copy to your scratchpad and use it for every worker.
> - `scripts/pm.py` — tolerant parser for `orca orchestration inbox/check` JSON (filters heartbeats by top-level `type`; supports `--json` for machine consumption).
> - `assets/{builder,integrator,reviewer,merge}_preamble.txt` — role templates for the four worker roles. Fill the `{{PLACEHOLDERS}}` from self-orientation.

---

## When to use / when NOT to use

**Use** when the user wants an autonomous, multi-agent pass that *fixes and lands* a backlog:
"clean sweep the issues", "close everything in this audit doc", "find and fix every real bug and
leave it green", "autonomous fix-everything run". The unit of work is a **confirmed finding**, and
the deliverable is a **merged PR per finding on an integration branch**, plus an end-to-end-verified
repo.

**Do NOT use** for: a single bug fix (just fix it), a read-only review/audit (use a review skill —
this skill *closes* findings, it does not just list them), or a "hand this off to another agent"
request (that is a full ownership transfer, not supervised orchestration). If the user has not asked
for autonomy across a *set* of issues, this is the wrong tool.

---

## The phase graph

```
SELF-ORIENT ──► REVIEW/INVENTORY ──► SKEPTIC-TRIAGE ──► FREEZE ──► BOOTSTRAP-BASE
                  (find findings)     (confirm real)    (lock)     (integration branch)
                                                                         │
                                                                         ▼
        ┌──────────────── PER-FINDING PIPELINE (fan out, bounded parallel) ───────────────┐
        │  build(@builder) → open-PR + bot-reconcile(@integrator) → build-blind review    │
        │  (@reviewer) → conflict-aware commit-preserving merge into BASE(@integrator) →    │
        │  worktree cleanup(coordinator)                                                    │
        └───────────────────────────────────────────────────────────────────────────────┘
                                                                         │
                                                                         ▼
                              ANTI-INFLATION E2E GATE ──► FINAL REPORT + HUMAN GATES
                          (clean install, real DB, critical-path)   (surface OPS/decisions)
```

Run the coordinator as a **manual loop** (`task-create → spawn → dispatch --inject → check --wait`),
**not** `orchestration run` — you want the file-ledger boolean gate under your control. Fall back to
`orchestration run` only if a long run repeatedly stalls on coordinator context limits.

---

## Variants — the source of items (absorbed skills)

The pipeline is the same; the **source** of the items to close changes. Declare it up front.

### `source=audit` (default) — findings from a scan/audit doc

Phase 1 INVENTORYs findings (a security/quality scan, a review, a frozen findings doc),
freezes them, then the per-finding pipeline closes each. This is the classic clean-sweep.

### `source=tracker` (absorbs `backlog-zero`) — drain the whole issue tracker

Items are OPEN TRACKER ISSUES, not audit findings. Phase 1 changes:

- **Denominator (two queries, not one):** record run-start `T0` FIRST. Then enumerate
  (1) every open issue in scope (`gh issue list --state open` / `orca linear list`),
  **paginated to the end** — a truncated listing silently fails the run; and (2) every
  issue CREATED or REOPENED since `T0` any state (catches issues opened+closed mid-run,
  class `externally-resolved`). Re-run BOTH queries each loop — **re-enumerate until dry**.
- **Skeptic-triage = reproduce-or-refute:** a bug issue is VERIFIED only by a red-capable
  reproduction (command + failing output in the report); non-reproducible → work the
  timing/env/state/random tree → still nothing → REFUTED with attempts logged, or
  `needs-human` if it implies private state. Duplicates: search by domain concept, not
  wording. Class ∈ real-bug · real-feature-small · refuted · duplicate · externally-resolved
  · needs-human · out-of-scope. Workers NEVER mutate the tracker.
- **Human batch gate:** closing REFUTED/duplicate issues is a one-way gate (per-batch, or a
  once-per-run recorded grant via gate-steward).
- **Per issue in the pipeline:** a bug gets a red repro→regression test first; a small
  feature gets a failing acceptance test first (no prior failing behavior to reproduce).
- **Close with evidence:** on verified merge, close the issue with the merge SHA + one
  completion comment linking PR and test. Fix-backed closes need no extra gate — the
  evidence chain is the authorization.
- **Convergence:** a full enumeration finds ZERO issues that are not closed-with-evidence
  or parked-with-a-human-approved-reason.

### `mode=triage-only` (absorbs `triage-to-fleet`) — verify, don't fix

Run Phase 1 (enumerate + reproduce-or-refute) behind human state-transition gates, and
STOP — no BASE bootstrap, no fix pipeline. Terminal contract: every in-scope issue has a
recorded verdict (verified/refuted/duplicate/needs-human) with evidence, and the human has
gated each tracker state change. Hand the verified `ready-for-agent` set to a `source=tracker`
run when the human wants fixes.

### `scope=label` (absorbs `ready-agent-drain`) — a single ready-for-agent label

`source=tracker` narrowed to one label (e.g. `ready-for-agent`) with the triage phase
skipped (these were pre-triaged): claim the issue by assigning it, implement+tdd on the
frontier, dual review, PR to BASE, capped concurrency. Same close-with-evidence contract.

---

## Phase 0 — SELF-ORIENTATION (run FIRST, no placeholders)

Target the repo you are invoked from. **Derive everything; do not ask the user.** Record each choice
in a `DECISIONS.md` at repo root (append a dated `CLEAN-SWEEP RUN` section). Discover and pin:

| Variable | How to derive |
|---|---|
| `{{REPO}}` | `gh repo view --json nameWithOwner -q .nameWithOwner` (or `git remote -v`). |
| `{{MAINTAINER}}` | `git config user.name` + `user.email`. **Every commit in the run is authored as this, with NO trailers** (see `references/hygiene.md`). |
| `{{BASE}}` | The integration branch you create (e.g. `<maintainer>/clean-sweep`). All finding branches fork it; approved PRs `--merge` into it. **MUST NOT equal `{{DEFAULT_BRANCH}}`** — enforce via `scripts/preflight.py --base {{BASE}}` and record the assertion result in `DECISIONS.md`. |
| `{{DEFAULT_BRANCH}}` | `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`. BASE→default promotion is **human-owned, out of scope** unless the user explicitly asks. |
| `{{TOOLCHAIN}}` | Node/pnpm/python version from `.nvmrc`, `engines`, `package.json`, `mise.toml`, etc. Pin it; workers must select it before building (e.g. `nvm use 24`). |
| `{{BUILD}}/{{LINT}}/{{TEST}}/{{TYPECHECK}}/{{E2E}}` | The real scripts from `package.json`/`Makefile`/`justfile`. Verify they run at baseline before you trust "green". |
| `{{BOT}}` | Which PR bot reviews here (Cursor BugBot login `cursor`, CodeRabbit, etc.)? Check recent merged PRs. If none, the bot-reconcile step is a no-op. |
| Baseline health | Run build/lint/test/typecheck ONCE on BASE. Record pre-existing failures. **"Green" for the run means "adds no NEW failures vs. baseline"**, not "zero errors" — otherwise inherited breakage blocks every PR. |
| Autonomy flags | See **Worker roster** (single canonical spec). |

**Preflight assertion (M-5 guardrail).** Before Phase 2, run `python3 scripts/preflight.py --base
{{BASE}}` — it verifies `{{BASE}} != {{DEFAULT_BRANCH}}`, that BASE exists, that BASE forks from the
default branch's history, and that `git`/`gh` are present. Add `--require-gitleaks` if the integrator
will scan. Abort the run and tell the user if it fails; write the preflight result into DECISIONS.md.

**RESUME check:** if a prior run already merged fixes, the open-issue count *overstates* remaining
work (findings fixed but issues never closed). Reconstruct the **delta** from `git log <fork>..HEAD`
and work only what has **no merged fix commit**. Do not re-fix already-landed findings. To PREVENT the
"fixed-but-not-closed" gap on this run, put every `Closes #N` in the **promotion PR** body (the one that
merges to the default branch), not just the per-fix-unit PRs that land on the non-default BASE — see
`references/learnings.md` #29.

---

## Phase 1 — REVIEW / INVENTORY → SKEPTIC-TRIAGE → FREEZE

1. **Inventory** the findings. If the user handed you an audit/review doc, that is your source of
   truth — read it. Otherwise dispatch reviewer workers across dimensions (reliability, concurrency,
   security, authz, multi-tenant isolation, data model, cost/abuse, coupling, ops blind spots,
   dependency hygiene, dead code, weak tests, secret leaks, a11y, critical path) to produce it.
2. **Skeptic-triage** every finding: is it *real* and *root-cause* (not a symptom)? Classify into
   **lanes** (below). Drop tautological or already-fixed items.
3. **FREEZE** the finding list into an immutable doc (e.g. `docs/adversarial-review.md`). Reviewers
   later grade **against the frozen doc**, never against the diff in isolation — this is what stops
   scope creep and lets build-blind review work.

### Three-lane discipline

- **Lane A — implement.** Confirmed, code-fixable findings. Full pipeline → merged PR. *Most work.*
- **Lane B — draft + gate for owner.** Requires human judgment the fleet must **not fabricate**:
  legal/policy text, trademark/naming, pricing/business strategy. Land the *code scaffolding* if any;
  surface the decision. Never invent the substance.
- **Lane 0 — refuse + surface.** Ops/deploy actions, live-credential changes, anything outside the
  repo. **MERGE ≠ DEPLOY.** Surface in the final report; never execute.

---

## Phase 2 — BOOTSTRAP the integration BASE

Create `{{BASE}}` off the true baseline HEAD (usually current HEAD, which may be ahead of the default
branch), push it to origin. Every finding worktree branches off `{{BASE}}`; approved PRs `--merge`
(never squash) into it. Keep the **ledger** (`docs/clean-sweep-progress.md`) on disk in the
coordinator worktree — commit it only in the final docs PR, so it never races the integrator merges.

---

## Phase 3 — PER-FINDING PIPELINE (the core loop)

For each Lane-A finding, drive this state machine (full detail + ledger schema + reviewed-SHA
invariant in `references/pipeline.md`). Each stage is a **fresh worker** — the builder must NOT be
the reviewer (build-blind review is the whole point):

1. **BUILD** — a `codex` builder implements the fix in a dedicated worktree/branch off `{{BASE}}`,
   adds a **real regression test** (one that fails if the fix is reverted), commits as `{{MAINTAINER}}`.
   Uses `assets/builder_preamble.txt`.
2. **OPEN PR + BOT-RECONCILE** — a fresh `claude` integrator opens the PR against `{{BASE}}`, waits
   for `{{BOT}}` (bounded poll: floor 3 min, cap 10 min), then **reconciles** the bot: accept valid
   findings, **normalize any bot-pushed commits** back to `{{MAINTAINER}}` + strip trailers (never
   squash), dismiss false positives with a reason. Scoped secret scan on the branch diff only (if
   `gitleaks` is on PATH — the compatibility list marks it Optional). Uses
   `assets/integrator_preamble.txt`.
3. **BUILD-BLIND REVIEW** — a *different* fresh `claude` reviewer that never saw the builder's
   conversation grades the diff **against the frozen finding's acceptance criteria**, actively tries
   to FAIL it (root cause? regressions? secret leak? is the test real or tautological?), and votes
   PASS/FAIL. Uses `assets/reviewer_preamble.txt`. **Coordinator records the reviewed head SHA** —
   this is the merge worker's `{{REVIEWED_SHA}}` invariant.
4. **MERGE** — on PASS, a fresh `claude` integrator does a **conflict-aware, commit-preserving merge**
   into `{{BASE}}` (`gh pr merge --merge --delete-branch`; rebase-onto-BASE + resolve if behind;
   normalize author/trailers first). **Never squash — preserve every commit.** The merge worker
   verifies `git diff {{REVIEWED_SHA}}..HEAD` is empty (modulo author-normalization) before merging;
   any tree-changing commit added post-review is escalated for re-review — the merge worker cannot
   author its own. Uses `assets/merge_preamble.txt`.
5. **WT_CLEAN** — coordinator removes the finding's worktree.

**Parallelism & collisions.** Fan out independent findings in bounded waves (≈3–5 workers). Findings
that touch the **same hot files** (routers, schema, migrations, shared config) must be **serialized**
— assign a merge order in the ledger and rebase later ones onto the merged earlier ones. Renumber
colliding DB migrations and update the migration journal (see learnings).

**Reliable dispatch (critical).** `dispatch --inject` pastes the prompt into a **claude** worker's
input box but does **not** submit it — the worker sits idle forever. **After every inject to a claude
worker, wait ~8s then `orca terminal send --terminal <h> --enter`** to submit, and verify a heartbeat
arrives; re-Enter if not. `codex` auto-submits. Use `scripts/spawn_worker.sh`, which bakes this in.
Re-dispatching to the *same* handle after reset is a no-op — recover a dead worker with a **fresh
terminal**. See `references/learnings.md` for the full list.

---

## Phase 4 — ANTI-INFLATION E2E GATE (do not skip)

**Green unit tests ≠ working product.** Per-PR reviews see only affected tests and miss integration
breakage. Before declaring done, dispatch ONE gate worker that, on the fully-integrated `{{BASE}}`,
runs a **fresh clean install on the pinned toolchain** and verifies against actual result state
(build/typecheck/lint clean, full test suite green, real DB schema push with table-count assertion,
critical-path integration tests asserting real outcomes). If it finds a real break, spawn a fix-unit,
merge it, re-gate. **Full procedure and the format-sweep-last rule live in `references/pipeline.md`
(Phase 4 detail).** A build-breaker caught here that every per-PR review missed is the norm, not the
exception — this gate is why the run is trustworthy.

---

## Phase 5 — FINAL REPORT (the only message to the user)

In fully-autonomous mode the **final completion report is the only message you send the user.**
Produce a readiness doc + report covering:

- Every Lane-A fix-unit: finding IDs, PR#, one-line summary — all merged, commit-preserving, correctly authored.
- The anti-inflation gate evidence (what was actually verified).
- **Lane B** decisions drafted and awaiting the owner (with *why* the fleet must not decide them).
- **Lane 0 / OPS** queue surfaced but NOT executed (deployments, env vars, credential rotation). MERGE ≠ DEPLOY.
- Follow-up findings discovered mid-run but out of scope.
- **Downstream human gates**, explicitly unchecked: BASE→default-branch promotion, deploy, Lane-B calls, OPS.

---

## Phase 6 — POST-RUN HOUSEKEEPING (offer it; do it if the user says yes)

Promotion is human-*owned* but not human-*only*: in practice users usually want the coordinator to
finish the job once the gate is green. **Offer** the following as an explicit final step (don't
silently assume, don't refuse). When the user says go, execute per `references/housekeeping.md`:

1. **Promote BASE → default branch** via a promotion PR whose body carries a `Closes #N` for every
   finding closed this run (auto-closes them all in one shot; see learnings #29, #38).
2. **Verify auto-close** fired; `gh issue close` any straggler with a linking comment.
3. **Reconcile stale branches** — MERGED / SUPERSEDED / UNMERGED classification; salvage real fixes
   the run missed rather than blind-delete UNMERGED branches.
4. **Fast-forward the working branch** to the default; stash leftover working-tree files first
   (recoverable, don't discard).

## Worker roster (the single canonical spec for `--dangerously-*` + max-effort flags)

Everything else (before-run asks, spawn_worker.sh, README) references this section. If you change a
flag, change it here and only here.

- **Builder:** `codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort="xhigh"`
  (auto-submits after inject).
- **Reviewer / Integrator / Merge:** `claude --dangerously-skip-permissions` (**needs the explicit
  Enter after inject** — see `scripts/spawn_worker.sh` and learnings #1).
- Builder terminal ≠ reviewer terminal — always fresh sessions for build-blind independence.
- A worker that blocks on an internal approval dialog defeats the run — the flags above prevent that.

These flags are what the "Authorize the fleet" before-run ask (§ BEFORE THE RUN #1) is granting.

## Hygiene

Commit + secret hygiene are non-negotiable and live in `references/hygiene.md`. The short version:
every commit authored `{{MAINTAINER}}` with NO trailers, never squash (preserve every commit); no
live secrets ever touch the run; scoped `gitleaks` on branch diffs only (skipped if not installed).

---

## Failure-mode quick reference

Read `references/learnings.md` for the full catalog (heavily annotated with the run each item was
learned on). The ones that will bite you first are catalogued at the top of that file — start there
before spawning your first worker.
