---
name: run-blackbox
description: >-
  Status dashboard + crash-resume for Orca orchestration runs, reconstructed from the
  runtime's own persisted provenance (tasks, dispatch contexts, worker_done payloads with
  filesModified/reportPath, heartbeat phases). Use when a coordinator died mid-run,
  "where is the run", "resume the fleet", run status synthesis, or auditing what a past
  run actually did. Fills the runtime's missing run-status view; the ledger becomes the
  cache it was always claimed to be.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). git for
  cross-verification. python3 for the vendored pm.py parser.
---

# Run-Blackbox — the run state lives in the runtime, not the conversation

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | the provenance: tasks, dispatch contexts, messages — persisted in SQLite across app restarts | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | reading provenance back into a dashboard / a resumed run | this repo |

## Why this exists

Every `worker_done` carries `filesModified` and `reportPath`; every heartbeat carries a
`phase`; every dispatch context records assignee, failure count, and timestamps — and it
all survives coordinator death, terminal closure, and app restart. There is no built-in
run-status view, and until now no skill read any of it back. The fleet ledgers say "git
is truth; the ledger is its cache" — this skill makes the runtime's provenance the third
leg: ledger (narrative) · git (code truth) · provenance (dispatch truth).

## Run scope — mandatory before any mode

Orchestration state is RUNTIME-GLOBAL: `task-list` returns every task from every run and
`task-list` has no run filter. The blackbox therefore requires a declared scope:

- **Primary key:** the run's coordinator terminal handle(s), from the fleet ledger header
  — task rows record `created_by_terminal_handle`, so scope = tasks created by those
  handles.
- **Secondary key:** the task ids the ledger itself lists (belt and braces; catches tasks
  created before the ledger recorded the handle).
- Everything else in `task-list` is OUT OF SCOPE: counted once in the dashboard footer
  ("N out-of-scope tasks present, untouched"), never triaged, never re-dispatched, never
  written into this run's ledger.

No ledger / no derivable scope → STATUS may render a clearly-labeled GLOBAL view;
RESUME must ABORT (resuming an unbounded scope can hijack another run's tasks).

## Mode 1 — STATUS (read-only, no side effects — renders to the session, writes no files)

```
1. orca orchestration task-list --json                 → filter to RUN SCOPE (above)
2. per dispatched/completed/failed task:
   orca orchestration dispatch-show --task <id> --json → assignee, failure_count,
                                                         last_heartbeat_at, timestamps
3. orca orchestration inbox --terminal <coordinator> --full --json > inbox.json
   python3 scripts/pm.py inbox.json                    → worker_done bodies, reportPaths,
                                                         escalations, parked gates
   (inbox --terminal mirrors check --all: it does NOT mark messages read — safe while
    another coordinator is live)
4. Render the dashboard:
   | task | status | assignee | fails | last phase | heartbeat age | reportPath |
   plus: gates open (gate-list --status pending), circuit-broken tasks, orphaned
   dispatches (dispatched + no live terminal in `orca terminal list`).
```

Use STATUS freely during a live run — it is the missing `runStatus`.

## Mode 2 — RESUME (after a coordinator died mid-run)

```
0. FREEZE  — confirm no other coordinator is acting (orca terminal list; a second live
             coordinator means STOP — hand findings to it instead).
1. REBUILD — run STATUS. For every task the provenance says completed, CROSS-VERIFY
             against git before trusting it (the fleets' own rule):
             worker_done.filesModified exist on the branch · PR state via gh where the
             task opened one · reportPath file exists.
             Provenance says done + git disagrees → mark the task SUSPECT, treat as
             failed, and note it — never re-mark by hand without evidence.
2. RECONCILE — rewrite the fleet ledger from the verified picture (the ledger is the
             cache; the blackbox is its recovery source). Parked gates and doctor-log
             entries carry over verbatim.
3. RE-ENTER — resume the fleet skill's coordinator loop exactly where the DAG says:
             ready tasks dispatch (spawn_worker v2 refuses anything the DAG disallows);
             `dispatched` tasks with dead terminals go to fleet-doctor triage (fresh
             terminal, failure budget intact — the runtime carried failure_count).
4. RECORD  — append a `## Resumed <date>` header to the ledger naming what was
             reconstructed, what was SUSPECT, and the provenance counts.
```

## Mode 3 — AUDIT (post-run, read-only)

Same reads as STATUS against a finished run: per-task wall-clock (dispatched_at →
completed_at), failure/respawn counts, phase timelines from heartbeats, reportPath
inventory. AUDIT is the one file-writing read mode: output
`docs/audits/run-<date>-<coordinator-handle>.md` (append `-2`, `-3` on collision). Feed
recurring stall patterns to `fleet-memory` (wave 2) as learnings.

## Completion contract

- STATUS: dashboard rendered with EVERY IN-SCOPE task accounted for — no "misc" rows —
  plus the out-of-scope count in the footer. No files written.
- RESUME: ledger rewritten, every SUSPECT called out, coordinator loop actually re-entered
  (or the run declared converged), and the Resumed header written. Reconstructing without
  re-entering is an audit, not a resume — say which one happened.
- AUDIT: every dispatched task appears with timestamps and an outcome.

## Rules

- Never `orchestration reset` to "clean up" — it destroys the blackbox. Reset is for
  abandoning a run wholesale, after an AUDIT snapshot.
- Provenance outranks the ledger; git outranks provenance claims about code.
- STATUS/AUDIT use `inbox` (non-destructive), never `check --unread` (marks read and
  steals messages from a live coordinator).

## Handoff contract

AUDIT emits `docs/audits/run-<date>-<coordinator-handle>.md` (STATUS writes nothing);
RESUME hands a reconciled ledger to the fleet skill and SUSPECT tasks to `fleet-doctor`.
`standing-fleet` invokes RESUME when a scheduled run's ledger has a header but no footer.

## Related

`fleet-doctor`, `standing-fleet`, `clean-sweep` / `spec-to-ship` (whose RESUME sections
this generalizes from git-only to git + provenance).

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the ledger schema RESUME reconciles into

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
