---
name: full-sprint-fleet
description: >-
  One coordinator chaining plan, build, verify, and ship using gstack and Matt skills
  under Orca. Use when full sprint fleet, autonomous sprint, or build and ship with fleet.
  Human gates for plan freeze, promote, and deploy.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# Full-Sprint-Fleet — end-to-end AFK sprint on Orca

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


## Phase graph
```
0 ORIENT + preflight
1 PLAN: office-hours-async and/or autoplan-fleet → FREEZE
2 BUILD: matt-ship or wayfinder-fleet→matt-ship or spec-to-ship
3 VERIFY: review-prod-fleet + review-matrix + qa-fleet (+ cso-fleet if auth-heavy)
4 SHIP: gstack-ship-fleet → human merge
5 optional: canary-fleet, docs-fleet
```

## Requires (runtime composition — the declared exception to the pack's no-cross-dependency norm)
This skill DISPATCHES other skills in this pack: `office-hours-async` / `autoplan-fleet`
(plan), `matt-ship` / `wayfinder-fleet` / `spec-to-ship` (build), `review-prod-fleet` +
`review-matrix` + `qa-fleet` (+ `cso-fleet`) (verify), `gstack-ship-fleet` (ship), optional
`canary-fleet` + `docs-fleet`. Install those, PLUS gstack AND the Matt skills (README
Tracks C + D), before running. A quick-start that symlinks only this skill cannot run.

## Rules
- Thin coordinator: dispatch only; no implementing.
- Single ledger for the whole sprint.
- Skip phases user marks out of scope; never skip preflight or human promote.
- We use Orca for all AFK parallelism — not subagents.

## Related
All gstack×Orca and Matt×Orca fleet skills.

**Handoff contract:** one sprint ledger (`docs/full-sprint-progress.md`) shared across
phases; each phase consumes the prior phase's `report_path` and `reviewed_sha` per the
AGENTS.md finding schema — a phase never re-scans what the prior phase already produced.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

