---
name: matt-ship
description: >-
  Coordinate Matt Pocock engineering skills on Orca from idea to shippable PR:
  grill-with-docs → (optional prototype) → to-spec → to-tickets → parallel
  implement(+tdd) on the ticket frontier → dual-axis code-review → integrate.
  Use when the user wants the full Matt main flow under supervised multi-agent
  orchestration, "matt ship", "idea to tickets to fleet implement", or AFK
  coding after grilling. Requires Orca + orchestration skill + mattpocock skills.
  Not for frozen-spec-only greenfield (use spec-to-ship) or audit close-out (use clean-sweep).
license: MIT
compatibility: >-
  Requires Orca multi-agent runtime (orchestration experimental on) and the
  companion orchestration skill from the Orca CLI. Matt skills installed
  (grill-with-docs, to-spec, to-tickets, implement, tdd, code-review, handoff,
  prototype). Worker CLIs codex/claude; git + gh; python3. Optional gitleaks, PR bot.
---

# Matt-Ship — idea → AFK fleet → PR

You are the **COORDINATOR** of a supervised Orca run that executes Matt Pocock's
**main engineering flow** with real multi-agent parallelism on the ticket frontier.

**You do not implement code or dual-role review.** You grill (HITL), freeze specs,
materialize a DAG from tickets, dispatch AFK workers, wait on `worker_done`, sequence
merges, and surface human gates.

## Hard dependencies

- Orca up + orchestration experimental; load **`orchestration`** (Orca CLI skill).
- Matt skills available to workers: `/grill-with-docs`, `/to-spec`, `/to-tickets`,
  `/implement`, `/tdd`, `/code-review`, `/handoff`, `/prototype`, `/domain-modeling`.
- Helpers: `scripts/orca-coord/spawn_worker.sh`, `preflight.py`, `pm.py` (repo root).

## Matt coding flow (authoritative)

```
align (grill) → to-spec → to-tickets → implement(+tdd) → code-review
```

If the idea is **foggy / multi-session**, chart with **`wayfinder-fleet` first**, then
**merge here at `/to-spec`** — do not stay in wayfinder for coding delivery (Matt v1.1+).

## Phase graph

```
SELF-ORIENT → ALIGN (grill-with-docs HITL)
  → optional PROTOTYPE detour (AFK worktree)
  → SPEC (to-spec) → FREEZE (human gate)
  → TICKETS (to-tickets) → materialize Orca DAG from Blocked-by
  → BUILD waves (implement+tdd per frontier ticket, worktrees)
  → REVIEW (dual-axis code-review workers, build-blind)
  → INTEGRATE (conflict-aware merge to BASE)
  → VERIFY (suite / e2e) → OPEN promotion PR (human)
```

## Phase 0 — Self-orient

Derive `{{REPO}}`, `{{MAINTAINER}}`, `{{DEFAULT_BRANCH}}`, `{{BASE}}` (integration branch
≠ default), toolchain, build/test commands, tracker config (`docs/agents/` from
`/setup-matt-pocock-skills`). Run `python3 scripts/orca-coord/preflight.py --base {{BASE}}`.
Ledger: `docs/matt-ship-progress.md` (boolean gates per ticket).

## Phase 1 — Align (HITL, coordinator only)

Run **`/grill-with-docs`** (+ `/domain-modeling`) on **this** terminal. Do not fan-out grilling.
Update `CONTEXT.md` / ADRs as the skill requires. Stop when the idea is sharp enough to spec.

## Phase 2 — Prototype detour (optional)

If a question needs a runnable answer: create supervised worktree worker with `/prototype`;
require `worker_done` + `reportPath`; fold learning into the thread via `/handoff` notes.
Do not promote prototype code into product.

## Phase 3 — Spec + freeze

Dispatch or run **`/to-spec`** → publish/write the spec. **Human freeze gate** before tickets.
No re-open of frozen scope without backlog entry.

## Phase 4 — Tickets → DAG

Run **`/to-tickets`**. After tracker publish:

1. For each ticket, `orca orchestration task-create --spec "<implement ticket …>" --deps '[…]'`.
2. Map **Blocked-by** to Orca deps (blockers first).
3. Hot-file collision map (package.json, routes, migrations) → **merge chains** (build parallel, merge serial).

## Phase 5 — Build waves

For each **ready** frontier ticket:

```bash
# worktree per ticket; builder = codex (or claude) with /implement + /tdd
# Use scripts/orca-coord/spawn_worker.sh
# Spec must require: maintainer author, no agent trailers, real regression tests, worker_done payload
```

Rules:

- One ticket per worktree; clear context (Matt smart-zone).
- Cap concurrency (~3–5).
- On `worker_done`, verify branch has commits; mark ledger `BUILT=t`.

## Phase 6 — Dual-axis review (build-blind)

For each built ticket, **two fresh terminals** (never the builder):

1. **Standards** axis of `/code-review` (fixed-point = BASE).
2. **Spec** axis against the ticket + parent spec.

Do not merge axes. FAIL → fix task; PASS → ready to merge.

## Phase 7 — Integrate + verify + promote

Conflict-aware commit-preserving merge into `{{BASE}}`. Re-run suite. Open BASE→default
promotion PR for human review. MERGE ≠ DEPLOY.

## Coordinator anti-patterns

- Grilling in a worker (HITL leak).
- Implement + review same terminal.
- Using wayfinder as the whole coding path after map complete (hand to to-spec instead).
- Trusting `worker_done` merge claims without `gh pr view` verification.
- Squash merges; agent trailers; live secrets in workers.

## Related peers

- `wayfinder-fleet` — foggy multi-session **before** this skill’s to-spec.
- `review-matrix` — review-only wall on an existing PR.
- `spec-to-ship` — frozen-spec greenfield (not Matt grill path).
- `clean-sweep` — audit findings, not tracker tickets.
