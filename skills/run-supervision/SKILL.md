---
name: run-supervision
description: >-
  Keep a long autonomous Orca run alive and recoverable. Two modes over the runtime's own
  provenance: WATCH (self-healing supervisor — detect stalled dispatches past the 10-min
  heartbeat window, respawn workers in fresh terminals, circuit-breaker escalation) and
  BLACKBOX (status dashboard, crash-resume, and post-run audit reconstructed from
  persisted worker_done / heartbeat / dispatch state). Use when a fleet stalls or goes
  silent, "revive the run", "where is the run", "the coordinator died", resume the fleet,
  self-healing run, or run status/audit. Runs alongside any fleet or mission.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). git for cross-verifying
  provenance against the tree. python3 for the vendored pm.py parser.
---

# Run-Supervision — don't lose a long run

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | dispatch contexts, `last_heartbeat_at`, `failure_count`, circuit breaker, persisted `worker_done`/heartbeat provenance (SQLite, survives restarts) | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | the recovery loop + the provenance reader on top | this repo |

## Why one skill

Two jobs that a coordinator always needs together for a long run: keep it moving while
it's alive (WATCH), and reconstruct/resume it if it dies (BLACKBOX). Both read the same
runtime provenance; the runtime already tracks everything, it just never acts on it. This
skill is the acting + reading layer, with the doctor's own state limited to its attempt
counter and log lines (never a shadow copy of runtime state).

## Mode WATCH — self-healing while the run is alive

```
LOOP until converged:
  1. check --wait --types worker_done,escalation,heartbeat --timeout-ms 300000
     ({count:0} timeout is the checkup tick, not an error)
  2. TRIAGE: for every dispatched task, dispatch-show → stale = no heartbeat past ~10 min
  3. ACT per stale: one Enter nudge (paste-not-submitted is the common stall) → still
     silent → RESPAWN
  4. RESPAWN (the stale task is still `dispatched`; spawn_worker refuses non-ready):
     a. doctor-log line FIRST (evidence + attempt N/3 — the doctor's OWN counter, not the
        runtime failure budget)
     b. task-update → ready ONLY after the dead-worker evidence line is written
     c. FRESH terminal (never re-dispatch a used handle — dispatch id null): spawn_worker
     d. exit 3 (no heartbeat) → loop; exit 1 (infra) → counts; exit 2 (state moved) →
        re-triage, uncounted
  5. BREAK: 3 doctor attempts OR runtime circuit_broken → escalate honestly: interactive
     → ask the human in-session (park A / reassign-as-new-task B / drop C); unattended →
     PARK with a gate-create hold. `ask` is agent-to-agent; never claim it reached a human.
```

## Mode BLACKBOX — status / resume / audit from provenance

**Run scope is mandatory** (state is runtime-global; `task-list` has no run filter): scope
= the run's coordinator handle(s) from the ledger header + the ledger's task ids;
everything else is counted-but-untouched. No ledger / no derivable scope → STATUS may show
a labeled GLOBAL view, RESUME must ABORT.

- **STATUS** (read-only, writes nothing): `task-list` + `dispatch-show` per task + `inbox
  --terminal --full` (non-destructive) via `pm.py` → dashboard (task · status · assignee ·
  fails · last phase · heartbeat age · reportPath) + open gates + orphaned dispatches.
- **RESUME** (coordinator died): freeze-check (no other live coordinator) → rebuild from
  provenance, CROSS-VERIFY every "completed" against git (filesModified on the branch, PR
  ancestry) before trusting it; provenance-says-done + git-disagrees = SUSPECT (treat as
  failed) → reconcile the ledger → re-enter the fleet's loop at the DAG frontier → write a
  `## Resumed <date>` header.
- **AUDIT** (post-run; reads state, writes ONLY the audit file): per-task wall-clock,
  failure/respawn counts, phase timelines, reportPath inventory → `docs/audits/run-<date>-
  <handle>.md` (collision-safe). Feed recurring stall patterns to `fleet-memory`.

## Completion contract

- WATCH: fleet converged — every task completed/failed/human-parked, no dispatched task
  without a live heartbeat, every circuit-broken/budget-exhausted task has a recorded human
  decision OR a PARKED hold. Doctor log lists every intervention.
- STATUS: dashboard renders every in-scope task (no "misc" rows) + the out-of-scope count;
  no files written.
- RESUME: ledger rewritten, every SUSPECT named, loop actually re-entered (or run declared
  converged) — reconstructing without re-entering is an AUDIT, say which happened.
- AUDIT: every dispatched task appears with timestamps and an outcome.

## Rules

- Runtime state is authoritative — never mark tasks completed by hand to unblock.
- Never `orchestration reset` to "clean up" — it destroys the blackbox; reset is for
  abandoning a run wholesale, after an AUDIT snapshot.
- Respawned workers inherit the ORIGINAL task spec verbatim; spec changes = a new task.
- STATUS/AUDIT use `inbox` (non-destructive), never `check --unread` (steals a live
  coordinator's messages).

## Handoff contract

Appends a `## Supervision log` to the supervised fleet's ledger; AUDIT emits
`docs/audits/...`; SUSPECT tasks and stalls feed `fleet-memory`. `standing-fleet` invokes
RESUME when a scheduled run's ledger has a header but no footer.

## Related

Every fleet and mission (supervision is generic), `standing-fleet`, `fleet-memory`, 
`gate-steward`, `merge-train`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the supervision/blackbox ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
