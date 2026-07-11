---
name: content-wayfinder
description: >-
  Non-coding wayfinder orchestration (courses, curricula, long-form content):
  keep the journey inside the map — research, outline grilling, prototypes of
  lessons, writing workers — without forcing /to-spec → implement. Use for course
  creation, content programs, or when Matt notes wayfinder as the whole flow for
  non-coding. For software features, use wayfinder-fleet then matt-ship instead.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt wayfinder, grilling, research, writing-*
  skills if present; scaffold-exercises optional.
---

# Content-Wayfinder

Matt’s note: wayfinder **can** be the entire flow for **non-coding** work (e.g. course
creation). This skill is that path under Orca.



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

## Contrast with coding

| | Coding | Content (this skill) |
|--|--------|----------------------|
| After map clear | `/to-spec` → tickets → AFK implement | Keep producing content artifacts on the map |
| Destination | Spec / shipped feature | Published module / lesson set / outline |
| AFK workers | implement+tdd | research, exercise scaffold, draft sections |

## Phase graph

```
CHART map (destination = ship content X)
  → LOOP frontier:
       research (parallel)
       grilling (HITL outlines)
       prototype (sample lesson / exercise)
       task (assets, recordings checklist)
  → optional writing workers (shape/beats/fragments if installed)
  → DONE when destination content exists and is linked from map
```

## Rules

- Still **one ticket per worker session**.
- HITL never self-answered.
- Prefer durable assets in-repo (`content/`, `course/`) linked from tickets.
- Do **not** auto-route to `matt-ship` unless the user pivots to software.

## Related

- `wayfinder-fleet` — coding-oriented wayfinder that exits to to-spec

## Scripts & assets (local to this skill)

Use paths relative to this skill directory (works inside worktrees when the skill is installed/linked):

- `scripts/spawn_worker.sh` — Orca terminal + `dispatch --inject` (does **not** replace Orca)
- `scripts/preflight.py` — BASE ≠ default branch
- `scripts/pm.py` — inbox/check helper
- `assets/*_preamble.txt` — builder / reviewer / researcher / redteam role text
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md` for the run

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.

