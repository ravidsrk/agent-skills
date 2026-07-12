---
name: design-shotgun-fleet
description: >-
  Orchestrate gstack design-shotgun under Orca: parallel variant generation, comparison
  board artifact, human pick. Use when design shotgun fleet or autonomous multi-variant UI
  exploration.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Design-Shotgun-Fleet — parallel UI variants on Orca

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
FRAME constraints
  → N design workers (isolated) each produce a radical variant (HTML/mock path)
  → board worker joins comparison board
  → human gate: pick / iterate
  → optional design-html finalize worker
```

Similar spirit to `design-it-thrice` but UI/visual and gstack design-shotgun methodology.

## Completion contract (embed verbatim in every worker TASK)
Each variant worker returns `reportPath` with the variant artifact path AND a named
statement of what makes it distinct from every other variant. The coordinator's comparison
board must list ALL variants; a missing variant means the fleet is NOT done. No variant is
promoted before the human pick gate.

## Related
`design-it-thrice`, `autoplan-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

