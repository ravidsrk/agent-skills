# Orchestration ledger (external brain)

Coordinator: re-read this file after every worker_done. Git is truth; this is the cache.

## Run meta
- Repo:
- BASE (integration branch):
- DEFAULT_BRANCH:
- Maintainer author:
- Started:
- Phase:

## Invariants
- [ ] Orca runtime up; orchestration experimental on; `orchestration` skill loaded
- [ ] BASE ≠ DEFAULT_BRANCH (preflight)
- [ ] No in-process Task/subagent substitutes for Orca dispatch
- [ ] We **use** Orca orchestration — we do not replace it

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
