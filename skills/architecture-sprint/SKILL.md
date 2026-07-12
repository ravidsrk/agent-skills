---
name: architecture-sprint
description: >-
  Orchestrate codebase health deepening: Matt improve-codebase-architecture
  survey → human picks deepenings → optional design-it-thrice → grill-with-docs
  → to-tickets → implement fleet. Use for architecture sprints, agent-readability
  upkeep, or "deepen this module under Orca". Not a free-for-all refactor.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt improve-codebase-architecture,
  codebase-design, grill-with-docs, to-tickets, implement. Optional design-it-thrice skill.
---

# Architecture-Sprint

Keep the codebase good for agents **without freelancing large refactors**.



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

## Phase graph

```
SURVEY (improve-codebase-architecture → HTML/report of deepenings)
  → HUMAN PICK 1–3 deepenings (gate)
  → optional DESIGN (design-it-thrice per pick)
  → ALIGN (grill-with-docs on chosen deepening)
  → TO-SPEC (Matt /to-spec — freeze the spec; the canonical fixed point that ticket
    acceptance criteria and the later Spec review axis are judged against)
  → TICKETS (/to-tickets) → IMPLEMENT FLEET (matt-ship phases from tickets)
  → REVIEW + integrate
```

## Rules

- Survey is **read-only** until human picks.
- Each deepening is a **vertical** ticket set, not “rewrite the world”.
- Wide mechanical renames: expand–contract batches (Matt to-tickets rules).
- Prefer deep modules (small interface, hidden complexity) over drive-by renames.

## Related

- `design-it-thrice` for interface exploration
- `matt-ship` for delivery after tickets

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

## Deepening rules

See `references/deepening-rules.md`.
