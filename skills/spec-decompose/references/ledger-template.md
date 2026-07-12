# Orchestration ledger (external brain) — spec-decompose

Coordinator: re-read this file after every worker_done. Git is truth; this is the cache.
The slice ↔ task-id table IS the run scope `run-blackbox` will need.

## Run meta
- Repo:
- BASE (integration branch):
- DEFAULT_BRANCH:
- Maintainer author:
- Started:
- Phase:
- Spec source (frozen path / issue):
- Spec freeze SHA / date:
- Chosen loop: runtime-coordinator | manual-wave
- allow-stale-base used? (reason if yes):

## Invariants
- [ ] Orca runtime up; orchestration experimental on; `orchestration` skill loaded
- [ ] BASE ≠ DEFAULT_BRANCH (preflight)
- [ ] No in-process Task/subagent substitutes for Orca dispatch
- [ ] We **use** Orca orchestration — we do not replace it
- [ ] Spec is FROZEN (human-gated) before cut
- [ ] Foreign pending/ready/dispatched tasks checked before `orchestration run`

## Slice ↔ task-id (run scope)
| slice id | title | kind (foundation\|slice\|hot-chain) | task_id | deps (task ids) | hot-files (must NOT touch / merge-chain) | acceptance (≤2 sentences) |
|----------|-------|-------------------------------------|---------|-----------------|-----------------------------------------|---------------------------|
| F1 | | foundation | | — | | |
| S1 | | slice | | F1 | | |

## DAG verification (before any dispatch)
- [ ] `task-list --json`: every row present
- [ ] deps resolve to real ids; no cycles
- [ ] foundation has no deps on slices
- [ ] every hot-file chain is a path, not a fan
- [ ] frontier ready set == foundation only (spot-check)

## Loop declaration
- Loop chosen:
- If runtime-coordinator: foreign-task precondition result (`task-list` clean? Y/N):
- If manual-wave: first wave task ids:

## Dispatch / wave log
| wave | task ids | dispatched at | worker_done / notes |
|------|----------|---------------|---------------------|
| 1 | | | |

## Tasks
| id | title | deps | BUILT | PR_OPEN | REVIEWED | MERGED | WT_CLEAN | notes |
|----|-------|------|-------|---------|----------|--------|----------|-------|
| T1 | | — | f | f | f | f | f | |

## Gates
| gate | question | status | resolution |
|------|----------|--------|------------|

## Decisions
-

## Human / OPS queue
- [ ] Promotion PR BASE → default
- [ ] Deploy (if any) — MERGE ≠ DEPLOY
