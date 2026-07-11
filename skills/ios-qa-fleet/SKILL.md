---
name: ios-qa-fleet
description: >-
  Orchestrate gstack ios-qa, ios-fix, and ios-design-review under Orca when a Mac and
  device or Tailscale daemon is available. Use when ios qa fleet or autonomous iPhone QA.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Worker CLIs
  codex/claude; git + gh. gstack installed for worker methodology where named.
  Optional: browse daemon, deploy config, device hardware as noted in SKILL body.
---

# iOS-QA-Fleet — device QA/fix on Orca

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


## Preconditions
- Mac with device or Tailscale `gstack-ios-qa-daemon`
- App build installable

## Process
```
ios-qa worker → findings
optional ios-design-review worker
if fix mode: ios-fix workers per P0 → re-qa
```

Escalate if daemon unreachable — do not fake device results.

## Related
`qa-fleet` (web), `review-prod-fleet`.


## Scripts & assets

- `scripts/spawn_worker.sh` · `preflight.py` · `pm.py` — call Orca
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

