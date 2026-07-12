---
name: standing-fleet
description: >-
  Turn one-shot Orca fleets into standing, scheduled autonomy: wire `orca automations`
  (cron/RRULE triggers, precheck gating, missed-run grace) to orchestration coordinator
  runs. Use when scheduling a fleet ("run the drain nightly", "weekly retro", "canary
  after every deploy window"), creating a recurring autonomous run, standing fleet, or
  cron-driven orchestration. Not for one-off runs — invoke the fleet skill directly.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI) + `orca automations`.
  The scheduled fleet skill (e.g. clean-sweep, gstack-fleet) and its
  own dependencies must be installed. Worker CLIs codex/claude; git + gh where the
  fleet needs them.
---

# Standing-Fleet — scheduled coordinator runs on `orca automations`

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Scheduling** | triggers, prechecks, missed-run grace, run history | **`orca automations`** |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | *what / when / why* of standing runs | this repo |

**Preflight:** `orca status --json` · orchestration experimental on · `orchestration` skill loaded · `orca automations list --json` works · the target fleet skill installed with ITS preflight green once manually before scheduling.

## Why this exists

Every fleet in this pack is a single bounded run: it ends when the coordinator's session
ends. `orca automations` is the runtime's own scheduler — cron/RRULE triggers, a
`--precheck` command that SKIPS the run on nonzero exit, missed-run grace, fresh-or-reused
sessions, and run history — but nothing wires it to `task-create` + coordinator loops.
This skill is that wiring: the automation's prompt bootstraps a coordinator that runs the
fleet skill, and the precheck makes empty runs free.

## Process

### 1. Choose the fleet + cadence (with the human, once)

Confirm: which fleet skill, trigger (`hourly` / `daily` / `weekdays` / `weekly` /
5-field cron / RRULE), `--time HH:MM`, and the standing budget (max workers, PROFILE
ceiling, fix budget if any). Scheduling a fleet is a standing authorization — get it
explicitly; never schedule `PROFILE=danger` work.

### 2. Write the precheck (skip-empty-runs guard)

The precheck runs bounded, exits 0 to proceed, nonzero to skip. Ship one per queue type:

```bash
# gh issue queue non-empty (clean-sweep):
test -n "$(gh issue list --label ready-for-agent --limit 1 --json number -q '.[0].number')"
# Linear queue non-empty:
test "$(orca linear list --filter assigned --json | python3 -c 'import sys,json;print(len(json.load(sys.stdin).get("result",{}).get("issues",[])))')" != "0"
# time-window / deploy-marker (canary): marker file newer than last run
test -f .deploy-marker && test "$(find .deploy-marker -mmin -90)"
```

### 3. Create the automation

```bash
orca automations create \
  --name "standing-<fleet>-<cadence>" \
  --trigger daily --time 02:30 \
  --repo <repo-selector> \
  --provider claude \
  --fresh-session \
  --missed-run-grace-minutes 120 \
  --precheck '<precheck command>' --precheck-timeout 60000 \
  --prompt "$(cat "$HOME/.claude/skills/standing-fleet/assets/standing-run-prompt.txt")"
```

(The prompt template lives beside THIS skill — `$HOME/.claude/skills/standing-fleet/assets/`
for a standard install, `skills/standing-fleet/assets/` in a repo checkout. Customize a
copy per step 4; your shell is usually in the target repo, so never a bare relative path.)

`--repo` gives each run a fresh worktree; use `--workspace` only for fleets that must
observe existing state (canary). `--fresh-session` keeps run N+1 clean — state lives in
the ledger, not the conversation.

### 4. The standing-run prompt (the coordinator bootstrap)

Customize `assets/standing-run-prompt.txt`. Its contract, in order:

1. Load the `orchestration` skill and the fleet skill named in the prompt.
2. Run the fleet's OWN preflight (including `preflight.py --mode` per its profile);
   abort the run (exit, no retry) on failure — the next trigger retries fresh.
3. Append a run-header line to the standing ledger `docs/standing/<name>.md`
   (`run N · <date> · trigger=<t> · precheck=passed`), then execute the fleet skill
   exactly as written — same gates, same profiles, same completion contracts.
4. Human gates DO NOT weaken, and parked gates must map back to REAL runtime state:
   - One-way decisions (anything the fleet or guard-policy names a human gate) → PARK:
     ledger HUMAN-queue line + `gate-create --task <id>` so the DAG holds the task. The
     run continues elsewhere or winds down. Taste questions follow `gate-steward`
     (steward resolves with pending-veto, batched in the run brief) — only fleet-declared
     human gates and one-way doors park.
   - NEXT run start: reconcile each ledger PARKED line by querying ITS OWN rows —
     `orca orchestration gate-list --task <task-id> --json` (NO status filter: a pending
     filter cannot tell resolved from pruned; the unfiltered per-task query can). Branch
     on what comes back:
     · gate present, status `resolved` → the resolution auto-injects into that task's
       next dispatch — re-dispatch it.
     · gate present, status `pending`, answer recorded in the ledger → apply it:
       `gate-resolve --id <gate> --resolution "<answer>"`, then re-dispatch.
     · gate present, status `pending`, no answer anywhere → still parked; carry the line.
     · no gate row / task absent from `task-list` (reset, pruned) → create a NEW task
       whose spec embeds the human's ledger-recorded resolution verbatim; no resolution
       recorded → the question parks again on the new task.
     Never treat a ledger line alone as a resolved runtime gate.
5. End with a run-footer: counts (tasks completed/failed/parked), reportPaths, and the
   next action if any.

### 5. Operate

- Run history: `orca automations list --json` for the automation id, then
  `orca automations runs --id <automation-id> --json`; `run --id <id>` triggers now.
- The standing ledger is the cross-run memory: parked gates, last reviewed SHA, streaks.
- Pair with `run-supervision` inside the run for stalled-worker recovery, and `run-supervision`
  to reconstruct any run that died mid-flight.

## Completion contract (embed in the automation prompt)

A standing run is DONE only when the ledger holds the run header AND footer with real
counts, every dispatched task reached `completed` / `failed` / parked-gate state (none
left `dispatched`), and every parked gate names its `decision_gate` id. A run that ends
without a footer is a crashed run — `run-supervision` reconstructs it.

## Rules

- One automation = one fleet = one ledger. No multi-fleet mega-prompts.
- PROFILE ceiling comes from the fleet's own SKILL.md (ro fleets stay ro on a schedule).
- Never schedule around a failing preflight — fix the fleet first.
- Disable (`orca automations edit --disabled`), don't delete, when pausing: run history
  is evidence.

## Handoff contract

Consumers read `docs/standing/<name>.md`: run footers carry `report_path`s (AGENTS.md
finding schema where the fleet emits findings) and parked `decision_gate` ids for
`gate-steward`.

## Related

`gstack-fleet` (the fleet this pattern generalizes), `clean-sweep`, `gstack-fleet`, 
`run-supervision`, `gate-steward`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `assets/standing-run-prompt.txt` — the coordinator bootstrap template (step 4)
- `references/ledger-template.md` — standing-ledger schema (run headers/footers + parked gates)

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
