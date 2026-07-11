---
name: full-sprint-fleet
description: >-
  One coordinator chaining plan, build, verify, and ship using gstack and Matt skills
  under Orca. Use when full sprint fleet, autonomous sprint, or build and ship with fleet.
  Human gates for plan freeze, promote, and deploy.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Full-Sprint-Fleet — end-to-end AFK sprint on Orca

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


## Phase graph
```
0 ORIENT + preflight
1 PLAN: office-hours-async and/or autoplan-fleet → FREEZE
2 BUILD: matt-ship or wayfinder-fleet→matt-ship or spec-to-ship
3 VERIFY: review-prod-fleet + review-matrix + qa-fleet (+ cso-fleet if auth-heavy)
4 SHIP: gstack-ship-fleet → human merge
5 optional: canary-fleet, docs-fleet
```

## Rules
- Thin coordinator: dispatch only; no implementing.
- Single ledger for the whole sprint.
- Skip phases user marks out of scope; never skip preflight or human promote.
- We use Orca for all AFK parallelism — not subagents.

## Related
All gstack×Orca and Matt×Orca fleet skills.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

