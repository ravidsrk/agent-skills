---
name: review-prod-fleet
description: >-
  Orchestrate gstack /review depth under Orca: parallel build-blind workers hunting bugs
  that pass CI but break in production (SQL, LLM trust, authz, conditional side effects).
  Use when prod review fleet, pre-landing review autonomous, or deeper than Standards/Spec
  axes.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Review-Prod-Fleet — production-bug class review on Orca

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


You are the **COORDINATOR**. Complements `review-matrix` (Matt Standards/Spec).

## Axes (parallel workers)
| Axis | Focus |
|------|--------|
| SQL / data | injection, N+1, missing transactions, migration safety |
| AuthZ | IDOR, role, tenant |
| LLM/tool trust | prompt injection, unsafe tool args, secret egress |
| Conditional side effects | flags, racey webhooks, partial failure |
| gstack /review umbrella | optional single worker running full skill |

## Process
1. Pin fixed point / PR
2. Parallel axis workers → reportPaths
3. Optional **codex second-opinion** worker (gstack /codex challenge)
4. Aggregate; do not fix unless user asked
5. Optional fix tasks for P0

## Related
`review-matrix`, `gstack-ship-fleet`, `cso-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

