---
name: health-fleet
description: >-
  Parallel Orca workers for gstack health-style metrics: typecheck, lint, tests, dead
  code, dependency hygiene joined into one dashboard artifact. Use when health fleet,
  quality dashboard autonomous, or pre-sprint baseline.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Health-Fleet — code quality dashboard on Orca

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
Parallel workers: typecheck | lint | unit/integration | dead-code/unused | deps audit
JOIN → docs/health-report.md (scores + top fixes)
optional: open tickets for P0 health breaks
```

Read-only by default. Fix only if user set fix-budget.

**Launch profile:** spawn workers with `PROFILE=ro` (`scripts/spawn_worker.sh` — sandboxed/plan-mode
agents, no bypass flags) and preflight with `--mode readonly`. Switch to `PROFILE=rw` only for the
fix-budget tasks themselves.

## Related
`benchmark-fleet`, `docs-fleet`, `cso-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

