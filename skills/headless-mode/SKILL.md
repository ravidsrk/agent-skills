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

## What gstack actually reads (there is no prose mode)
gstack derives its session kind from the ENVIRONMENT (`bin/gstack-session-kind`), not from
preamble text. A TASK line saying "SESSION_KIND=headless" changes nothing.

- `GSTACK_HEADLESS=1` → gstack `headless`: when a question cannot be asked, gstack
  **BLOCKS** (Completion Status BLOCKED). It does NOT auto-select an answer for UNTUNED
  questions. (Exception: a per-question `never-ask` preference from gstack plan-tune
  auto-decides BEFORE the headless fallback; one-way doors always override `never-ask`.
  Preferences are PROJECT-persistent — `~/.gstack/projects/<slug>/question-preferences.json`
  — so worker sessions in the same repo inherit whatever the user has tuned; a project
  with no plan-tune history blocks on everything.)
- Spawned sessions (e.g. OpenClaw-launched) are the mode that auto-selects the
  `(recommended)` option.
- Anything else is interactive.

## Process
1. Launch every worker with the env var actually set, via the launcher overrides:
   `CLAUDE_CMD='GSTACK_HEADLESS=1 claude --permission-mode acceptEdits' scripts/spawn_worker.sh …`
   (same pattern for `CODEX_CMD`).
2. Rules injected into every worker TASK — written to work WITH the blocking semantics:
   - never call AskUserQuestion (it hangs a headless session)
   - when gstack blocks on a question, do NOT invent an answer: raise
     `orca orchestration ask` to the coordinator, or `worker_done` with status blocked +
     the question list
   - taste / premise / irreversible decisions always escalate; log every decision taken
     in the report
3. Coordinator turns blocked questions into `decision_gate`s for the human.
4. Auto-decided review questions come from two places, and only two: gstack's own
   per-question `never-ask` preferences (project-persistent plan-tune state, see above),
   and **autoplan's AUTO_DECIDE** where the COORDINATOR answers blocked questions per
   autoplan's decision principles with an audit trail. Do not promise workers that gstack
   headless will self-answer UNTUNED questions — those block until the coordinator replies.

## Related
`guard-policy`, `autoplan-fleet`, `full-sprint-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

