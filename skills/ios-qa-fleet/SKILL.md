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

## Concrete device/emulator-worker mechanics

- The active emulator is WORKSPACE-scoped (one per workspace): parallel mobile QA means
  either one worker per WORKTREE-workspace (each `orca emulator attach`es its own
  simulator) or a single serialized emulator lane — never two workers driving one
  emulator.
- Commands take normalized 0-1 coordinates (`tap 0.5 0.85`), so specs stay
  resolution-independent; read the accessibility tree (`orca emulator ax`) to target
  semantically before falling back to coordinates.
- iOS runs via serve-sim (macOS only); Android shells to adb — declare which lane in the
  TASK, the two have different failure modes (simulator boot vs adb device offline).
- Evidence per finding: screenshot before/after, the ax-tree node targeted, and the
  gesture sequence — a repro someone can replay on a fresh simulator.
- Permissions/camera-injection state persists on the simulator between tasks: reset to a
declared baseline at task start (`permissions`, `camera`), or findings bleed across
  axes.
- Lifecycle per lane: `orca emulator attach` at task start; boot/attach failure = the
  TASK fails with the error captured (never silently fall back to another simulator —
  that invalidates the axis's device claim); at wind-down `orca emulator kill` what you
  attached and record it in the ledger.

## Related
`qa-fleet` (web), `review-matrix`.


## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/*_preamble.txt` — worker roles
- `references/ledger-template.md` — copy to `docs/<skill>-progress.md`

Workers should load **gstack** skills when the TASK names them (`/review`, `/qa-only`, `/cso`, …). Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup`

