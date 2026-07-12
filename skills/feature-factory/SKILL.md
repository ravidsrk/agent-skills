---
name: feature-factory
description: >-
  Autonomous mission: one human grill + spec freeze, then hands-off to a shipped feature.
  After the frozen spec, the fleet decomposes to tickets, implements each as a tested
  vertical slice PR, build-blind reviews, merge-trains onto an integration branch,
  verifies end-to-end, and opens the promotion PR behind a human gate — with a
  post-promotion canary. Use when "build and ship this feature", feature factory, spec
  to shipped feature, or an autonomous build-to-ship run. Peer of spec-to-ship (whole
  product); this is single-feature scoped with a front-loaded grill.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh. Worker
  playbooks: mattpocock/skills (grill-with-docs, to-spec, to-tickets, implement, tdd) or
  addyosmani/agent-skills (spec-driven, planning, incremental-implementation, /build
  auto) — one router per worker. In-pack: spec-decompose, merge-train, gate-steward,
  fleet-doctor, run-blackbox, canary-fleet.
---

# Feature-Factory — one grill in, a shipped feature out

You are the **COORDINATOR** of an autonomous mission with ONE human-in-the-loop phase
(the grill + freeze) and ONE human gate (promotion). Between them it runs unattended.
The end state is EVIDENCE: the feature is live behind the promotion gate, every
acceptance criterion has a passing test, and the canary is green.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | grill→freeze→build→ship phases, gates | this repo |
| **Worker playbooks** | grill/spec/tickets/implement/tdd | Matt main flow OR Addy DEFINE→BUILD |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · clean baseline (never absorb unrelated WIP — the /build-auto rule) · tests
green at baseline (you can't tell your regressions from pre-existing ones otherwise).

## Mission parameters

- `{{BASE}}` integration branch · `{{MAX_WORKERS}}` (~3-5) · `{{FEATURE}}` one-line intent
- `{{DEPLOY}}` who owns promotion+deploy (default: human gate opens PR, OPS deploys) ·
  `{{CANARY_URL}}` if a post-promotion canary applies.

## Phase graph

```
GRILL (HITL) → SPEC + FREEZE (human gate #1)
  → DECOMPOSE (spec-decompose DAG) → BUILD waves (tested slices, PR-per-ticket)
  → build-blind REVIEW → merge-train onto BASE → VERIFY e2e on BASE
  → open PROMOTION PR (human gate #2) → [human merges] → CANARY → REFLECT
```

## Phase 1 — GRILL + FREEZE (the only interactive phase)

On the COORDINATOR terminal (never fan grilling out to a worker — HITL leak): run
`grill-with-docs` (Matt) or `interview-me` + `spec-driven-development` (Addy) —
relentless one-question-at-a-time, recommend an answer to each, look facts up in the
codebase, put every DECISION to the human. Produce a frozen spec with objectives,
acceptance criteria per capability, boundaries (explicit NOT-in-scope), and the test
strategy.

**Human gate #1 — FREEZE:** the human confirms the spec. No re-opening frozen scope
without a backlog entry. This freeze is the canonical fixed point every downstream Spec
review and acceptance test is judged against.

## Phase 2 — DECOMPOSE

Hand the frozen spec to **spec-decompose**: tracer-bullet vertical slices sized one
context window, foundation-first (scaffold/data/seams/test-harness serialize; slices
parallelize), hot-file merge chains identified, DAG materialized via `task-create
--deps` and verified (no cycles, correct frontier). Ledger:
`docs/feature-factory-progress.md` with the slice↔ticket↔task table.

## Phase 3 — BUILD waves

Per ready ticket (DAG order), `PROFILE=rw` worker in its own worktree
(`--base-branch {{BASE}}`), TASK = the implement+tdd contract:

- **Failing acceptance test first** for the slice's criterion (Prove-It), then the
  smallest implementation, then refactor at a correct seam.
- Scope discipline: touch only what the ticket requires; note adjacent issues, don't
  fix them (they become backlog, not scope creep).
- Commit-per-slice, staged files only, author {{MAINTAINER}}, no trailers.
- Anything irreversible or high-risk (auth, destructive migration, payments, deletes,
  secrets, deploy) STOPS and escalates via `ask` — the /build-auto stop-and-ask list.

Build-blind REVIEW per slice (fresh terminal; Matt `/code-review` once, or review-matrix
rubrics — Standards + Spec against the frozen criterion). FAIL → fix task (≤3 rounds
then BLOCKED). PASS → `merge_ready` → **merge-train** onto `{{BASE}}` (ancestry-verified).

Stalls → **fleet-doctor**. Decisions → **gate-steward** (mechanical audited; taste
batched to a decision brief; one-way human).

## Phase 4 — VERIFY end-to-end on BASE

After all slices merge, a fresh worker runs the FULL suite + the e2e/acceptance tests
against `{{BASE}}` HEAD, and maps EVERY frozen acceptance criterion → the test that
proves it (a traceability table). A criterion with no passing test is UNMET work — a new
slice, not a waiver. Missing infra the plan assumed done (a store that was never
persisted) surfaces here as a task, not a shrug.

## Phase 5 — PROMOTE + CANARY

- Open the `{{BASE}}`→default **promotion PR** with the traceability table in the body.
- **Human gate #2 — PROMOTION:** merge to default is one-way; the human decides. The
  mission NEVER self-merges the promotion or deploys (merge ≠ deploy).
- On promotion + `{{CANARY_URL}}`: hand to **canary-fleet** (baseline-relative, alert on
  change, 2-consecutive confirmation, human rollback gate). The mission owns opening the
  canary; OPS owns the rollout.

## Completion contract (evidence)

- Frozen spec exists and was human-approved (gate #1 reference in the ledger).
- Every acceptance criterion → a passing test, in the traceability table, verified on
  `{{BASE}}` HEAD (not per-slice-only — the integrated whole).
- Every slice: merged PR (ancestry-verified) + a test that failed before the slice
  (revert-audited on a sample).
- Promotion PR opened with the traceability table; gate #2 recorded. If the human
  merged: canary opened and its first-window verdict recorded.
- Backlog file of noted-not-fixed adjacent issues (scope discipline made visible).

## RESUME

`run-blackbox` RESUME scoped to this ledger; the slice DAG and merge state reconcile
against git + `gh pr` (ancestry). Never re-run a merged slice; re-enter at the frontier.
A dead coordinator mid-BUILD resumes without re-grilling — the frozen spec is durable.

## Anti-patterns

- Fanning the grill out to a worker (the human's side of a HITL grill is never
  agent-substituted).
- Skipping the freeze and decomposing a moving spec (tickets and Spec review lose their
  fixed point — the architecture-sprint bug).
- Per-slice green mistaken for feature-done (Phase 4 verifies the integrated whole).
- Self-merging the promotion or deploying (both are human/OPS, always).
- Two playbook routers in one worker TASK (conflicting spec/TDD definitions).

## Handoff contract

Emits the mission ledger (slice table, gates, traceability), review findings in the
AGENTS.md schema, and REFLECT learnings to `fleet-memory`. `canary-fleet` consumes the
deploy handoff; `standing-fleet` is NOT typical here (features are one-shot missions),
but a backlog of frozen specs can be queued.

## Related

`spec-to-ship` (whole-product peer), `matt-ship` (the supervised Matt-flow sibling),
`spec-decompose`, `merge-train`, `gate-steward`, `fleet-doctor`, `run-blackbox`,
`canary-fleet`, `gstack-ship-fleet` (ship phase).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the slice/traceability ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
