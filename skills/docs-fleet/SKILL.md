---
name: docs-fleet
description: >-
  Orchestrate gstack document-generate and document-release under Orca after code lands.
  Use when docs fleet, autonomous docs, or Diataxis generation post-ship.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Docs-Fleet — generate + release docs on Orca

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
DETECT what shipped (BASE vs default / last tag)
  → document-generate worker (tutorial/how-to/reference/explanation gaps)
  → document-release worker (sync existing docs to behavior)
  → dual light review (accuracy only)
  → PR to BASE
```

Never invent product claims not supported by code. Human gate on user-facing doc PRs if public.

## Completion contract (embed verbatim in every worker TASK)
Every claim in generated docs must trace to a file/symbol that exists at the stated path —
the report lists the spot-checks performed. `worker_done` lists every doc file written and
its Diataxis quadrant. Documenting an API that does not exist in the tree fails the task.

## Related
`gstack-ship-fleet`, `matt-ship`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

