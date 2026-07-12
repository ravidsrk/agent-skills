---
name: gstack-fleet
description: >-
  Run any gstack command across parallel Orca workers and join the results into one
  report — the parameterized fleet for gstack methods that don't need bespoke worker
  mechanics (ship, health, canary, retro, office-hours, and any other /gstack-command).
  Use when "run gstack <X> as a fleet", ship fleet, health dashboard, canary monitor,
  retro batch, office-hours prep, or any gstack command fanned across Orca workers. For
  browser/device mechanics use qa-fleet / ios-qa-fleet; for the plan gauntlet use
  autoplan-fleet.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); garrytan/gstack for the
  worker methodology; git + gh where the command needs them. Worker CLIs codex/claude.
---

# Gstack-Fleet — one parameterized fleet for gstack commands

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the parameterized fan-out + join | this repo |
| **Worker methodology** | the gstack command's own playbook | garrytan/gstack |

**Preflight:** `orca status --json` · orchestration on · `orchestration` skill loaded ·
gstack installed · `scripts/preflight.py` with the profile for `{{COMMAND}}` (readonly for
report-only commands, write for fix/ship commands).

## Why this is one skill, not many

The gstack fleets that only "run a gstack command across parallel workers and join to a
report" share the same coordinator: fan out per axis/target, wait on `worker_done`, join.
The only thing that changed between them was the command and the PROFILE. This skill is
that shape, parameterized — replacing the former per-command wrapper skills
(the ship / health / canary / retro / office-hours fleets).

## Parameters

- `{{COMMAND}}` — the gstack command (`/ship`, health metrics, canary monitor, `/retro`,
  office-hours prep, or any other). `{{TARGETS}}` — axes/URLs/scope to fan across.
- `{{PROFILE}}` — `ro` for report-only (health, canary, retro, benchmark-style), `rw` only
  for fix/ship commands. Never `danger`.
- `{{REPORT}}` — the joined artifact path (`docs/<command>-report.md`).

## Command table (the former wrappers, now modes)

| Mode | Command | Profile | Join artifact | Notes |
|------|---------|---------|---------------|-------|
| ship | gstack `/ship` (+ optional land/canary) | rw | PR + ship log | human gates: merge, deploy. Consumes prior review evidence (AGENTS.md routing) — no duplicate test/review pass. |
| health | typecheck · lint · tests · dead-code · deps | ro | `docs/health-report.md` | one worker per check; scored dashboard. |
| canary | post-deploy monitor (browse/health endpoints) | ro | `docs/canary-report.md` | baseline-relative, alert on change, 2-consecutive; human rollback gate; coordinator files the incident issue. |
| retro | gstack `/retro` on git history | ro | `docs/retros/YYYY-WW.md` | scheduling belongs to `standing-fleet`; this is the single batch run. |
| office-hours | research pack + six forcing questions | ro→rw synth | `docs/gstack-fleet.md` | never answer the six questions as the human; stop with blockers if unanswered past timeout. |
| other | any `/gstack-command` | per command | `docs/<command>-report.md` | pick PROFILE by whether the command writes. |

## Process

```
ORIENT → per TARGET, task-create a worker whose TASK = "load gstack {{COMMAND}}, run it on
  <target>, worker_done with reportPath" → dispatch (PROFILE per the table) →
  check --wait until all worker_done → JOIN reports into {{REPORT}} → human gate for any
  fix/merge/deploy the command implies.
```

## Completion contract

The joined `{{REPORT}}` exists with every target's result (exit codes / findings / the
command's own output pasted, not summarized), every dispatched worker reached
`completed`/`failed`, and any write action (fix, ship, merge) is behind its human gate.
A report missing a target is NOT done.

## Rules

- One command per run; don't multiplex commands into one mega-fleet.
- PROFILE from the table — report-only commands stay `ro` + preflight `--mode readonly`.
- Scheduling is `standing-fleet`'s job, not this skill's (retro/canary on a cron → wrap
  THIS skill in a standing automation).
- Commands with bespoke worker mechanics are their OWN skills, not modes here:
`qa-fleet` (browser page ownership), `ios-qa-fleet` (device lanes), `autoplan-fleet`
  (the sequential CEO→design→eng→DX gauntlet + headless execution model).

## Handoff contract

Emits `{{REPORT}}`; ship mode consumes prior review evidence and hands merges to
`merge-train`; scheduling to `standing-fleet`.

## Related

`qa-fleet`, `ios-qa-fleet`, `autoplan-fleet` (the gstack fleets with distinct mechanics), 
`standing-fleet` (scheduling), `merge-train`, `full-sprint` composition in AGENTS.md.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the per-command report ledger

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the *what/when/why*; gstack supplies the worker method.
