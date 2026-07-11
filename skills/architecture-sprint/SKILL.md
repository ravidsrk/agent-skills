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

## Phase graph

```
SURVEY (improve-codebase-architecture → HTML/report of deepenings)
  → HUMAN PICK 1–3 deepenings (gate)
  → optional DESIGN (design-it-thrice per pick)
  → ALIGN (grill-with-docs on chosen deepening)
  → TICKETS → IMPLEMENT FLEET (matt-ship phases from tickets)
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
