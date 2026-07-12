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

## Enforce, don't advise
Policy that lives only in prose is a false safety signal. This skill activates real
controls; the written doc just records them.

1. Ask/derive the freeze directory (or repo root read-write with careful defaults).
2. Activate the controls per worker kind:
   - **claude workers** (requires gstack installed): the worker TASK's FIRST steps are
     `/guard` then `/freeze <dir>` — real gstack PreToolUse hooks (careful returns
     permission "ask" on destructive Bash; freeze DENIES Edit/Write outside the dir).
     Hooks are session-scoped, so EVERY worker session must run them at start.
   - **codex workers**: gstack hooks do not apply — the control is the sandbox:
     `PROFILE=rw` (workspace-write) or `PROFILE=ro`. Never launch codex with bypass flags
     under guard-policy.
   - **fleet-wide**: `PROFILE=danger` is FORBIDDEN while guard-policy is active — the
     coordinator must not set `ORCA_COORD_ALLOW_DANGER`.
3. Write `docs/guard-policy.md` recording: freeze path, active hook set per worker kind,
   the PROFILE ceiling, and the precedence rules below.
4. Append the policy block to every worker TASK preamble (context for the model — the
   hooks and sandbox above are the actual control boundary).
5. **gstack not installed?** Then claude workers have NO hook enforcement. The doc and
   every preamble block MUST open with "ADVISORY ONLY — install gstack for enforced
   guard/freeze", and the coordinator degrades workers to `PROFILE=ro` wherever the
   fleet allows it.
6. Workers must refuse tasks that violate policy and `worker_done` with blocked reason.

## Precedence (one rule set, no contradictions)
- Freeze path beats any TASK instruction: an instruction to edit outside the freeze dir
  is refused, not negotiated.
- Workers never force-push. Integrator/merge ROLES may use `--force-with-lease` exactly
  where their preamble scripts it (bot-commit normalization, rebase-then-push); that
  narrow preamble grant wins over this skill's general no-force-push default.
- `--admin` merges only under the run's recorded human D8 grant (spec-to-ship gotcha #1).
- Human gates are never self-approved: typed confirm text comes from the human, through a
  `decision_gate` / `reply`, never composed by a worker.

## Related
`headless-mode`, all fleet skills.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

