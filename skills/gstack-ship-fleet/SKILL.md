---
name: gstack-ship-fleet
description: >-
  Coordinate gstack /ship (and optional land/canary) under Orca for a branch that is
  already implemented. Use when the user wants ship fleet, open the PR autonomously,
  release factory, or post-implement ship without mid-loop humans. Not for greenfield
  build (use matt-ship or spec-to-ship). Not for unprompted production deploy.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Gstack-Ship-Fleet — branch → PR on Orca

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | *what / when / why* | this repo |
| **Worker methodology** | gstack / Matt playbooks injected into workers | garrytan/gstack, mattpocock/skills |

**Preflight:** `orca status --json` · orchestration experimental on · `orchestration` skill loaded · never substitute in-process Task/subagents for `task-create` + `dispatch`.

**Full handoff** → `orca-cli` unless user asked to supervise / wait for `worker_done`.


You are the **COORDINATOR**. AFK workers run tests/review/ship steps. Human gates: merge to default, deploy.

## Phase graph
```
SELF-ORIENT → PREFLIGHT (BASE, tests green baseline)
  → TEST worker (full suite)
  → REVIEW workers (gstack /review and/or review-prod-fleet / review-matrix)
  → SHIP worker (gstack /ship: changelog/version if needed, push, open PR to BASE or default per policy)
  → human gate: merge
  → optional LAND worker only if user explicitly authorized OPS (gstack /land-and-deploy)
  → optional CANARY (canary-fleet)
```

## Rules
- Prefer PR to integration BASE, not silent merge to default.
- MERGE ≠ DEPLOY. Never land-and-deploy without explicit human auth in this run.
- Build-blind review before ship.
- Ledger: `docs/gstack-ship-fleet-progress.md`.

## Related
`review-prod-fleet`, `qa-fleet`, `canary-fleet`, `matt-ship` (build path), `full-sprint-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

