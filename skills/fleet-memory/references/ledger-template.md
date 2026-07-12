# Orchestration ledger (external brain) — fleet-memory

Coordinator: re-read this file after every worker_done. Git is truth; this is the cache.
Memory with no ledger trace is superstition.

## Run meta
- Repo:
- BASE (integration branch):
- DEFAULT_BRANCH:
- Maintainer author:
- Started:
- Phase:
- Fleet name (for inject match):
- Store: `docs/fleet-memory/learnings.jsonl` + `specialist-stats.jsonl`

## Invariants
- [ ] Orca runtime up; orchestration experimental on; `orchestration` skill loaded
- [ ] BASE ≠ DEFAULT_BRANCH (preflight)
- [ ] No in-process Task/subagent substitutes for Orca dispatch
- [ ] We **use** Orca orchestration — we do not replace it
- [ ] Secrets never enter the JSONL store
- [ ] Specialist ids from the canonical table (see fleet-memory SKILL.md)

## Injected keys (per dispatched task)
| task id | injected keys (≤5, selection order applied) | selection rule echo |
|---------|---------------------------------------------|---------------------|
| | | confidence desc → date desc → key asc; fleet match then tag intersection |

## Worker echoes
| task id | prior learning applied (keys) | notes |
|---------|-------------------------------|-------|
| | | |

## Specialist stats / gating (this run)
| specialist id | dispatched? | gated? | reason (e.g. 0/10+) | findings count | stats line appended? |
|---------------|-------------|--------|---------------------|----------------|----------------------|
| standards | | | | | |
| spec | | | | | |
| security-lite | | NEVER_GATE | | | |
| test-adequacy | | | | | |
| sql | | NEVER_GATE | | | |
| authz | | NEVER_GATE | | | |
| llm-trust | | | | | |
| side-effects | | | | | |

NEVER_GATE (always run): `security-lite`, `authz`, `sql`.

## REFLECT writes
- Learnings appended (keys) / explicit "nothing ≥15 min":
- Superseded / retired keys this run:

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
