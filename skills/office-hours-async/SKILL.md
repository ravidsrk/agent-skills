---
name: office-hours-async
description: >-
  Async autonomous prep for gstack office-hours: research pack and six forcing questions
  written to a ledger; human answers offline; agent continues planning. Use when async
  office hours, office hours without blocking, or AFK product interrogation prep.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Office-Hours-Async — YC office hours without live chat block

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


## Process
```
RESEARCH workers (optional research-then-grill / monid)
  → WRITE six forcing questions + premises to docs/office-hours-async.md
  → decision_gate / wait for human answers (or poll file section Answers:)
  → SYNTHESIZE design doc for autoplan-fleet / matt-ship
```

## Rules
- Never answer the six questions as the human.
- If answers missing after timeout, stop with clear blockers list.
- HITL taste preserved; only prep is AFK.

## Related
`autoplan-fleet`, `research-then-grill`, `wayfinder-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

