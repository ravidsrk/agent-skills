---
name: retro-cron
description: >-
  Run gstack retro as an autonomous Orca batch cron-friendly: commit history, streaks,
  per-person breakdown to a report artifact or issue. Use when retro cron, weekly retro
  autonomous, or automation schedule.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Retro-Cron — weekly eng retro on Orca

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
one batch invocation:
  retro worker (gstack /retro methodology on git log)
  → write docs/retros/YYYY-WW.md
  → optional open tracking issue
```

No code changes. Safe for scheduled automations (`orca automations`).

## Related
`health-fleet`, `landing-report` (gstack) as inputs.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

