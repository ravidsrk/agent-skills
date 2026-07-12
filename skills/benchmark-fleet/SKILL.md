---
name: benchmark-fleet
description: >-
  Orchestrate gstack benchmark under Orca against staging URLs for Core Web Vitals or load
  versus baseline. Use when benchmark fleet or perf regression autonomous.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Benchmark-Fleet — perf regression on Orca

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
INPUT: URL(s) + baseline artifact (optional)
  → benchmark worker(s) per URL or journey
  → compare to baseline / prior run
  → report + optional tickets for regressions > threshold
```

Read-only. No performance-fix work without separate implement tasks.

**Launch profile:** spawn workers with `PROFILE=ro` (`scripts/spawn_worker.sh` — sandboxed/plan-mode
agents, no bypass flags) and preflight with `--mode readonly`. A measurement fleet never needs
write-capable workers.

## Completion contract (embed verbatim in every worker TASK)
A `worker_done` is valid ONLY with `reportPath` containing a per-URL/journey metrics table
(numeric values, tool used, run count), the baseline values compared against, and the delta
with a regression verdict per threshold. No baseline comparison = NOT done.

## Related
`health-fleet`, `qa-fleet`, `canary-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

