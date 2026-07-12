---
name: ephemeral-fleet
description: >-
  Disposable cloud/VM workers for Orca fleets: stand up per-workspace environments from
  repo-owned recipes (orca.yaml environmentRecipes), pair each remote runtime via
  orca serve, dispatch work into them, destroy on completion. The sanctioned home for
  danger-profile work — bypass flags in a sandbox that ceases to exist. Use when
  untrusted or heavy parallel work shouldn't run on your machine, "run the fleet in
  sandboxes", disposable workers, or ephemeral CI-like fleets.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI) + orca-per-workspace-env
  skill (recipe lifecycle) with a validated recipe (orca vm recipe doctor). A sandbox
  provider (Vercel Sandbox / Docker / VM / SSH host) with agent-auth snapshots.
---

# Ephemeral-Fleet — workers that stop existing

## ⚠️ HARD BASE: Orca `orchestration` + `orca-per-workspace-env`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, provenance | Orca |
| **Environments** | recipe lifecycle: create / suspend / resume / destroy, pairing | **`orca-per-workspace-env`** (repo `orca.yaml` `environmentRecipes`) |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | fleet-shaped use of ephemeral environments | this repo |

## Why this exists

`danger`-profile work (bypass flags) on your own machine violates least privilege no
matter how careful the prompt — guard-policy forbids it outright. Disposable environments
dissolve the tension: full autonomy INSIDE a sandbox whose credentials are scoped
snapshots and whose disk stops existing at teardown. The runtime supports this today —
recipes stand up environments, `orca serve --recipe-json` inside one emits a pairing
code, and a paired remote worktree's terminals dispatch like any local worker — but no
skill composed the two.

## Prerequisites (once per repo — see `orca-per-workspace-env` for the full setup)

1. `environmentRecipes` in `orca.yaml` with the create/suspend/resume/destroy scripts.
2. Agent-auth snapshot baked (the interactive-auth phase of the recipe setup) — workers
   in the sandbox authenticate from the snapshot, never from your live keychain.
3. `orca vm recipe doctor --provision` green. A fleet on an unvalidated recipe is a
   debugging session with a billing meter.

## Process

```
1. SIZE    — N sandboxes for N parallel lanes (one worker per sandbox; sandboxes are
             the isolation unit, don't multiplex strangers into one).
2. CREATE  — per lane, the recipe's create path. Two connection modes (recipe-defined):
             · orca-server: create runs `orca serve --recipe-json` in the sandbox and
               emits a pairingCode → pair it (Orca app/CLI) → the remote worktree and
               its terminals appear as dispatch targets.
             · ssh: create emits a connection.type:"ssh" target — terminals open over
               SSH; same dispatch surface once attached.
3. DISPATCH — task-create as usual; dispatch to the REMOTE worktree's terminals
             (`--worktree "path:<remote worktree path>"` per the pairing). PROFILE=danger
             is permitted HERE with ORCA_COORD_ALLOW_DANGER=1 — record the sanction in
             the ledger: "danger sanctioned: ephemeral sandbox <id>, destroyed after".
4. HARVEST — worker_done carries reportPath/filesModified as usual, but the DISK IS
             MORTAL: anything worth keeping leaves via git push (to the integration
             BASE) or an explicit artifact copy BEFORE teardown. The completion contract
             below makes this non-optional.
5. DESTROY — the recipe's destroy path, per sandbox, as soon as its lane converges.
             Suspend/resume only for deliberate multi-day lanes with a written reason.
             Verify destruction (provider list) — a forgotten sandbox is a standing
             credential surface and a bill.
```

## Completion contract

A lane is DONE only when: its work is verifiably OFF the sandbox (branch pushed and
visible on origin, or artifacts copied and paths recorded), `worker_done` received, the
sandbox is destroyed, and the ledger row reads
`lane <n> · sandbox <id> · pushed <branch@sha> · destroyed <timestamp>`. A lane whose
sandbox died before the push is a FAILED lane — rerun it; never mark it done from memory
of what the worker said.

## Rules

- Danger profile: sanctioned ONLY inside ephemeral sandboxes, recorded per-lane in the
  ledger. On your own machine guard-policy still says never.
- Secrets: the sandbox gets the auth SNAPSHOT the recipe baked — never inject live
  credentials at dispatch time; a task spec containing a secret is a spec bug.
- Anything not pushed before DESTROY never happened — schedule harvest before teardown,
  not after.
- Cost is part of the ledger: lanes record create/destroy timestamps; a standing
  "ephemeral" sandbox older than the run is a finding.

## Handoff contract

Pushed branches land in the normal pipeline: `merge-train` for BASE sequencing,
review fleets for evidence. The ledger's lane table (sandbox id, pushed SHA, destroyed
timestamp) is the audit trail `run-blackbox` AUDIT consumes.

## Related

`orca-per-workspace-env` (the lifecycle this composes), `guard-policy` (why danger
lives here), `merge-train`, `clean-sweep` / `spec-to-ship` (fleets worth sandboxing).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the lane table extends

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
