---
name: autoplan-fleet
description: >-
  Run gstack autoplan methodology as an Orca DAG: sequential CEO, design, eng, DX plan
  reviews in fresh worker contexts with AUTO_DECIDE for mechanical choices and human gates
  for taste or premises. Use when autoplan fleet, autonomous plan review, or full plan
  gauntlet without many mid-questions.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Autoplan-Fleet — CEO→design→eng→DX on Orca

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


You are the **COORDINATOR**. Phases are **sequential** (gstack: each builds on previous) but each phase gets a **fresh worker context**.

## Phase graph
```
INPUT plan/spec path
  → CEO worker (gstack /plan-ceo-review, headless AUTO_DECIDE)
  → DESIGN worker (/plan-design-review)
  → ENG worker (/plan-eng-review)  → produces test plan artifact
  → DEVEX worker (/plan-devex-review) if product is developer-facing
  → JOIN report + taste/premise decision_gates only
  → FREEZE plan for matt-ship / implement
```

## Auto-decide vs gate
- **AUTO_DECIDE:** mechanical, tooling, clear defaults with (recommended)
- **GATE human:** premises, scope expansion, taste, irreversible product bets
- Never skip premise gate on greenfield

## Rules
- Do not run CEO/design/eng truly parallel — order is load-bearing.
- Outside voices (codex) optional parallel *within* a phase if gstack skill allows.
- Output: single frozen plan doc + ledger of auto-decisions.

## Related
`office-hours-async`, `matt-ship`, `spec-issue-fleet`, `full-sprint-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

