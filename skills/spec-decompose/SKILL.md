---
name: spec-decompose
description: >-
  Fill Orca's missing decomposition step: turn a spec into a tracer-bullet vertical-slice
  task DAG (task-create --deps) sized one-context-window-per-task, then hand it to the
  runtime coordinator (orchestration run with auto-provisioning) or a manual wave loop.
  Use when "decompose this spec", "build the task DAG", spec to task graph, or when
  orchestration run throws "No tasks found" — the runtime requires pre-created tasks and
  performs no AI decomposition itself.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). A frozen spec (from
  Matt /to-spec, gstack /spec, or equivalent). Optional Matt /to-tickets when its
  tracker conventions are wanted.
---

# Spec-Decompose — the DAG the runtime expects but cannot build

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, deps, readiness, dispatch, the `orchestration run` coordinator loop | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This skill** | spec → slices → `task-create --deps`, and the choice of loop | this repo |

**Runtime facts:** `orchestration run --spec` stores the spec text for context only — it
does NOT generate tasks, and errors with "No tasks found" on an empty DAG. Only one
coordinator run can be active. Default `--max-concurrent` is 4; with `--worktree` set the
coordinator auto-provisions one worker terminal per tick when ready tasks outnumber idle
workers, and a worktree >20 commits behind base silently SKIPS dispatch unless the spec
carries `allow-stale-base: true`.

## Input contract

A FROZEN spec (human-gated). Foggy idea → `wayfinder-fleet` / grill first; this skill
does not interview, it cuts. Re-decomposing after freeze = backlog entry, not a new DAG.

## Process

### 1. Cut vertical slices (tracer bullets)

- Each slice: narrow but COMPLETE through every layer it touches — demoable, testable,
  one fresh context window of work (the Matt sizing rule; if you can't state the slice's
  acceptance check in two sentences, cut smaller).
- Wide mechanical refactors don't slice vertically: sequence them expand → migrate-in-
  batches → contract, each batch its own task, CI green throughout.
- Name the FOUNDATION set (scaffold, data layer, seams, test harness) — it serializes;
  slices parallelize behind it.
- Hot mount-point files (route registry, DI wiring, migrations, barrels) → mark each as
  a merge-chain: slices touching one share a dependency chain, never run in parallel.

### 2. Materialize the DAG

Per slice, in topological order (blockers first — deps must name EXISTING task ids):

```
orca orchestration task-create \
  --spec "<slice spec: goal · exact acceptance check · files it may create ·
          hot-files it must NOT touch · worker_done requires reportPath>" \
  --task-title "<S3 payments-webhook>" --deps '["<id-of-F1>","<id-of-S1>"]' --json
```

Record every returned task id in the ledger (`docs/spec-decompose-<slug>.md`): the
id ↔ slice table IS the run scope `run-supervision` will need.

### 3. Choose the loop — declared, not drifted into

- **Runtime coordinator** (hands-off): `orca orchestration run --worktree <selector>
  --max-concurrent <N>` — auto-provisions workers, dispatches the frontier, warns on
  stalls (it does not self-heal: pair `run-supervision`). One active run only; `run-stop`
  before starting another. **Scope hazard — check before launch:** the coordinator loop
  dispatches READY tasks from the runtime-GLOBAL table, not just yours. Precondition:
  `task-list --json` shows no foreign pending/ready/dispatched tasks (only this DAG's
  ids from the ledger table). Foreign active tasks present → use the manual wave loop
  below, which dispatches only your ids. There is no run-status RPC — `run-supervision`
  STATUS is the dashboard. Base drift >20 commits skips dispatch silently: sync the
  worktree's base before waves, and add `allow-stale-base: true` to a task spec only
  with a written reason in the ledger.
- **Manual wave loop** (the pack's fleets): dispatch ready tasks yourself via
  `scripts/spawn_worker.sh`, wait on `check --wait`, sequence merges via `merge-train`.
  Pick this when you need per-wave human gates or merge-chain choreography the runtime
  coordinator doesn't know about.

### 4. Verify the DAG before dispatching anything

`task-list --json`: every task present · deps resolve to real ids · no cycles (walk it)
· foundation tasks have no deps on slices · every hot-file chain is a path, not a fan.
A malformed DAG dispatched is a fleet-wide debugging session; five minutes here is cheap.

## Completion contract

DONE when: the ledger holds the full slice ↔ task-id table, `task-list` shows the DAG
with correct deps (spot-check the frontier: exactly the foundation is ready), the chosen
loop is declared in the ledger, and either the run is launched or the first wave is
dispatched. A decomposition nobody dispatched is a proposal, not a decomposition.

## Rules

- One spec → one DAG → one ledger. Parallel specs get parallel decompositions.
- Never `--mark-ready` around the DAG you just built (spawn_worker v2 will refuse
  unmet deps anyway — that refusal means YOUR deps are wrong, fix the DAG).
- Slices sized to one context window; a worker asking for a `/handoff` mid-slice means
  the slice was too big — split it in the backlog, don't extend the worker.

## Handoff contract

Emits the ledger with the id ↔ slice table (run scope for `run-supervision`), hands
merge sequencing to `merge-train`, stalls to `run-supervision`, and gates to
`gate-steward`. `matt-ship` Phase 4 is the tracker-integrated sibling; this skill is
the tracker-less direct path.

## Related

`matt-ship` (tracker-first sibling), `spec-to-ship` (whose foundation/slice discipline
this reuses), `run-supervision`, `merge-train`, `standing-fleet`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — ledger schema with the slice ↔ task-id table

Load the Orca **`orchestration`** skill for command grammar. This skill only supplies *what/when/why*.
