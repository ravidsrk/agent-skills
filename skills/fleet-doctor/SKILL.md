---
name: fleet-doctor
description: >-
  Self-healing supervisor for a running Orca fleet: detects stalled dispatches (no
  heartbeat past the runtime's 10-minute staleness window), respawns workers in FRESH
  terminals, lets the dispatch circuit-breaker (3 failures) bound retries, and escalates
  to a human only when the circuit breaks. Use when a fleet stalls, workers go silent,
  "revive the run", self-healing fleet, or supervising a long autonomous run. Runs
  INSIDE a coordinator session alongside any fleet skill.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). The supervised fleet's
  own dependencies. Worker CLIs codex/claude. python3 for the vendored helpers.
---

# Fleet-Doctor — detect, respawn, escalate

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | dispatch contexts, `last_heartbeat_at`, `failure_count`, circuit breaker | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the recovery loop on top of what the runtime already tracks | this repo |

## Why this exists

The runtime already persists everything recovery needs — heartbeats every ~5 minutes,
stale-dispatch detection at 10 minutes (2× cadence), `failure_count` carried across
dispatch contexts via MAX, `circuit_broken` at 3 failures — but the coordinator only
WARNS on staleness; it never acts. This skill is the acting layer. It adds no state of
its own: the dispatch table is the truth.

## The doctor loop (run in the coordinator, interleaved with the fleet's own waits)

```
LOOP until fleet converged:
  1. WAIT   — orca orchestration check --wait --types worker_done,escalation,heartbeat \
                --timeout-ms 300000   (a {count:0} timeout is the checkup tick, not an error)
  2. TRIAGE — for every task in `task-list --json` with status=dispatched:
              orca orchestration dispatch-show --task <id> --json
              → stale = last_heartbeat_at older than 10 min (or null past first poll window)
  3. ACT    — per stale dispatch, in order:
              a. one nudge: orca terminal send --terminal <handle> --enter  (paste-not-
                 submitted is the most common stall; harmless if already running)
              b. still silent after one more poll → RESPAWN (step 4)
  4. RESPAWN — never re-dispatch to the same handle (a handle that had this task returns
              dispatch id null — README Learnings L2). Fresh terminal:
                scripts/spawn_worker.sh <task> <worktree-selector> <title>-retry<N> <agent>
              spawn_worker exit 3 (dispatched, no heartbeat) feeds back into this loop;
              exit 1/2 → treat as a failed attempt (the runtime increments failure_count
              on failDispatch; do NOT reset task state by hand).
  5. BREAK  — task reached circuit_broken / failed after 3 attempts → STOP retrying.
              Escalate to the human:
                orca orchestration ask --to <human-facing coordinator> \
                  --question "task <id> circuit-broke after 3 respawns: <last error>.
                              Park (A), reassign to <other agent> as a NEW task (B),
                              or drop with rationale (C)?" --options "A,B,C"
              Record the answer in the fleet ledger. Reassignment = a NEW task-create
              (fresh failure budget is deliberate and visible), never a silent reset.
  6. ESCALATION messages from workers (type=escalation) route the same way: they already
     fail the dispatch server-side — triage the reason, don't just respawn the same spec.
```

## Diagnosis table (before any respawn, read the evidence)

| Signal | Likely cause | Action |
|--------|--------------|--------|
| No heartbeat ever, terminal alive | prompt pasted, never submitted | nudge Enter once, then respawn |
| Heartbeats stopped mid-run | worker crashed / context exhausted | respawn fresh; task spec unchanged |
| `worker_done` ignored by runtime | wrong sender or stale dispatch id | read `worker_done` authority rules (orchestration skill); the LATEST dispatch's assignee must send it |
| escalation with payload.taskId | worker hit a real blocker | fix the blocker (spec, env, deps) BEFORE respawning |
| repeated failure on one task, others fine | bad task spec, not bad workers | stop; rewrite the spec as a new task; escalate if unsure |

## Completion contract

The doctor is DONE when the fleet converges: every task `completed` / `failed` /
human-parked, no dispatch in `dispatched` state without a live heartbeat, and every
circuit-broken task has a recorded human decision (A/B/C above) in the ledger. A doctor
that "fixed" a fleet by silently dropping tasks is not done.

## Rules

- The dispatch table is authoritative — never mark tasks completed by hand to unblock.
- Respawn budget is the runtime's circuit breaker (3). Never work around it by resetting
  task status; reassignment is a NEW task with rationale.
- Respawned workers inherit the ORIGINAL task spec verbatim (drift between attempts makes
  failures undiagnosable). Spec changes = new task.
- Never respawn `PROFILE=danger` workers without re-confirming `ORCA_COORD_ALLOW_DANGER`
  is still intended for this run.

## Handoff contract

Appends a `## Doctor log` section to the supervised fleet's ledger: one line per
intervention (`task · signal · action · attempt N/3 · outcome`). `run-blackbox` consumes
this when reconstructing a crashed run; `standing-fleet` prompts embed this skill for
unattended runs.

## Related

`standing-fleet`, `run-blackbox`, every fleet skill in this pack (the doctor is generic).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema the doctor log extends

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
