---
name: qa-fleet
description: >-
  Orchestrate gstack /qa and /qa-only under Orca: parallel browse axes against a staging
  URL, optional bounded auto-fix, re-verify. Use when qa fleet, autonomous QA, browser
  test staging, or multi-axis dogfood. Requires gstack browse capability.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# QA-Fleet — browse QA factory on Orca

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


You are the **COORDINATOR**. Workers drive real browser QA (gstack `/browse` + `/qa-only` or `/qa`).

## Inputs
- Staging/base URL (required)
- Optional test plan path (from plan-eng-review)
- Mode: **report-only** (default) or **fix-budget N** (max N fix PRs)

## Phase graph
```
ORIENT → spawn axes in parallel:
  critical-path / auth-session / forms / mobile-viewport / a11y-smoke
Each: qa-only worker → reportPath with repro + screenshots
JOIN → severity board
if fix-budget: fix workers for top P0s → re-qa workers
human gate: accept residual risk
```

## Rules
- Default is **qa-only** (no code changes) unless user asked to fix.
- Fix budget is hard cap; leftover → backlog issues.
- Never use credentials beyond provided test accounts; no production writes.
- Pair with `setup-browser-cookies` is human/setup — not auto in fleet.

## Related
`review-prod-fleet`, `cso-fleet`, `gstack-ship-fleet`, `full-sprint-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

