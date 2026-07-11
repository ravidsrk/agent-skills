---
name: guard-policy
description: >-
  Policy skill that injects gstack careful, freeze, and guard constraints into every Orca
  worker preamble for a run. Use when guard policy, safe autonomous run, directory freeze
  for fleet, or destructive-command warnings on all workers.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Guard-Policy — careful/freeze/guard preambles for a fleet run

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
This skill **configures** other fleets. Apply at start of matt-ship / full-sprint-fleet / clean-sweep / etc.

## Process
1. Ask/derive freeze directory (or repo root read-write with careful defaults)
2. Write `docs/guard-policy.md` with rules:
   - no force-push, no rm -rf, no drop DB, no production secrets
   - freeze path if set
   - require explicit typed confirm text only for human gates (workers never self-approve destructive)
3. Append policy block to every worker TASK / assets preamble for this run
4. Workers must refuse tasks that violate policy and worker_done with blocked reason

## Related
`headless-mode`, all fleet skills.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

