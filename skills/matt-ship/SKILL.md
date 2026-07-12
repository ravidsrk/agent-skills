---
name: matt-ship
description: >-
  Coordinate Matt Pocock engineering skills on Orca from idea to shippable PR:
  grill-with-docs → (optional prototype) → to-spec → to-tickets → parallel
  implement(+tdd) on the ticket frontier → dual-axis code-review → integrate.
  Use when the user wants the full Matt main flow under supervised multi-agent
  orchestration, "matt ship", "idea to tickets to fleet implement", or AFK
  coding after grilling. HARD dependency: Orca runtime + orchestration skill (Orca CLI) + mattpocock skills.
  Not for frozen-spec-only greenfield (use spec-to-ship) or audit close-out (use clean-sweep).
license: MIT
compatibility: >-
  HARD dependency: Orca multi-agent runtime (orchestration experimental on) and the
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

## We have Orca — we do not replace it

This skill **uses** the Orca multi-agent runtime and the `orchestration` skill. It is a strategy layer on top of Orca, not a substitute harness. Never reimplement task/dispatch/worker_done with in-process subagents.

## Hard dependencies

- Orca up + orchestration experimental; load **`orchestration`** (Orca CLI skill).
- Matt skills available to workers: `/grill-with-docs`, `/to-spec`, `/to-tickets`,
  `/implement`, `/tdd`, `/code-review`, `/handoff`, `/prototype`, `/domain-modeling`.
- Helpers: `scripts/spawn_worker.sh`, `preflight.py`, `pm.py` — vendored beside this skill (repo checkout canonical: `scripts/orca-coord/`).

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
`/setup-matt-pocock-skills`). Run `python3 skills/matt-ship/scripts/preflight.py --base {{BASE}}` (repo checkout) or `python3 <skill-install-dir>/scripts/preflight.py --base {{BASE}}` (standalone install).
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
# Use this skill's vendored scripts/spawn_worker.sh (canonical: scripts/orca-coord/)
# Spec must require: maintainer author, no agent trailers, real regression tests, worker_done payload
```

Rules:

- One ticket per worktree; clear context (Matt smart-zone).
- Cap concurrency (~3–5).
- On `worker_done`, verify branch has commits; mark ledger `BUILT=t`.

## Phase 6 — Dual-axis review (build-blind)

For each built ticket, review build-blind (never the builder's terminal). Two faithful shapes —
upstream Matt `/code-review` has NO single-axis mode, so never dispatch "Standards only":

- **Default:** ONE fresh reviewer terminal runs Matt `/code-review` (fixed-point = BASE) once;
  it spawns its own Standards + Spec subagents. Consume both axes from its report.
- **Orca-native split:** two fresh terminals, each with a self-contained axis rubric from
  `review-matrix` (Standards: repo standards + smell baseline; Spec: against ticket + parent
  spec, quoting spec lines) pasted into the TASK — this pack's rubric, not a Matt mode.

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

## Variants (absorbed skills)

- **front-end=spec-issue** (was `spec-issue-fleet`): replaces Phase 1-3 (grill→spec→freeze)
  when the spec should live in the tracker. Steps:
  1. Run gstack `/spec` on the intent to produce a structured spec.
  2. Materialize it as a tracker ISSUE (`gh issue create` / `orca linear`) — the issue body
     IS the frozen spec + acceptance criteria; that issue is the **single source of truth**
     the human freezes (the freeze gate = the human confirming the issue).
  3. Enter Phase 4 (to-tickets → DAG) FROM the issue; each ticket references the issue.
  4. Preserve close-on-merge linkage: the implement PRs say `Closes #<issue>` so the source
     issue closes when the work merges; verify the close after the promotion, like any merge.
  Downstream (Phases 4-7) is the normal Matt flow.

## Related peers

- `wayfinder-fleet` — foggy multi-session **before** this skill’s to-spec.
- `review-matrix` — review-only wall on an existing PR.
- `spec-to-ship` — frozen-spec greenfield (not Matt grill path).
- `clean-sweep` — audit findings, not tracker tickets.

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

