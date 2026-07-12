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
  4. RESPAWN — the stale task is still `dispatched`, and spawn_worker v2 refuses anything
              but ready. The sanctioned recovery transition, in this exact order:
              a. EVIDENCE + LOG: doctor-log line FIRST — `task <id> · dead-worker evidence:
                 <no heartbeat since T / terminal gone> · attempt <N>/3` (N is the
                 DOCTOR'S OWN counter in the log — respawns do not consume the runtime
                 failure budget; that budget counts real dispatch failures).
              b. RE-READY: orca orchestration task-update --id <task> --status ready --json
                 — permitted HERE ONLY because the worker is evidenced dead and the line
                 above is written. This is recovery, not the forced-ready antipattern.
              c. FRESH TERMINAL: never re-dispatch to a handle that had this task
                 (dispatch id null — README Learnings L2):
                   scripts/spawn_worker.sh <task> <worktree-selector> <title>-retry<N> <agent>
              d. EXIT CODES: 3 (dispatched, no heartbeat) → counts, loop continues.
                 1 (infra step failed) → counts. 2 (refusal: task no longer pending/ready)
                 → the state MOVED under you (late worker_done, another actor) — re-triage
                 from step 2, do NOT count an attempt.
  5. BREAK  — 3 doctor attempts spent, OR the runtime marks the dispatch circuit_broken
              (real dispatch failures, e.g. repeated inject errors) → STOP retrying.
              Escalate to the human — honestly:
              · Interactive session (a human drives this coordinator): put the question
                to them directly — park (A), reassign as a NEW task (B), drop with
                rationale (C) — and record the answer in the ledger.
              · Unattended: PARK — ledger HUMAN-queue entry naming task, evidence, and
                the A/B/C options, plus `gate-create --task <id>` so the DAG holds it.
                There is no runtime channel that reaches a human: `ask` is agent-to-agent
                (worker→coordinator). Never claim an ask reached a person.
              Reassignment = a NEW task-create (fresh, visible budget), never a reset.
  6. ESCALATION messages from workers (type=escalation) already fail their dispatch
     server-side — triage the stated reason; fix spec/env first, don't respawn blind.
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
- TWO budgets, don't conflate: the doctor's respawn counter (3, kept in the doctor log —
  respawns don't increment the runtime's failure_count) and the runtime circuit breaker
  (3 real dispatch FAILURES → circuit_broken). Either tripping means BREAK.
- The step-4b `task-update → ready` is legal only with the evidence line written first;
  anywhere else it is the forced-ready antipattern spawn_worker v2 exists to prevent.
- Cadence numbers (~5 min heartbeats, 10 min staleness) are the runtime's documented
  defaults — judge staleness from `dispatch-show` timestamps you actually read, not from
  the folklore number.
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
