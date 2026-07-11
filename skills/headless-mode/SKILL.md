---
name: headless-mode
description: >-
  Policy skill that forces gstack headless session semantics on Orca workers: no
  AskUserQuestion, AUTO_DECIDE mechanical choices, escalate taste to coordinator
  decision_gate. Use when headless mode, fully autonomous gstack workers, or
  non-interactive fleet runs.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Headless-Mode — gstack headless/AUTO_DECIDE rules for Orca fleets

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


## Not a fleet by itself
Apply at coordinator start for any fleet that invokes gstack methodology.

## Rules injected into every worker TASK
1. `SESSION_KIND=headless` — do not call AskUserQuestion
2. AUTO_DECIDE options marked (recommended); log decision in report
3. Taste / premise / irreversible → `ask` / escalation to coordinator (not invent)
4. On missing human: `worker_done` with status blocked + questions list
5. Coordinator turns blocks into `decision_gate` for the user

## Related
`guard-policy`, `autoplan-fleet`, `full-sprint-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

