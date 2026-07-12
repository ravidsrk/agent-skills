# Orchestration ledger (external brain) — quorum

Coordinator: re-read this file after every worker_done. Git is truth; this is the cache.
A vote you can't audit from the rows below didn't happen.

## Run meta
- Repo:
- BASE (integration branch):
- DEFAULT_BRANCH:
- Maintainer author:
- Started:
- Phase:
- Mode: VOTE | JURY
- QUORUM-ID (QID):
- Poll deadline T: (default: max(20m, N_voters × 10m), cap 2h)
- Quorum rule (declared up front): majority of votes cast, min 2, abstentions excluded

## Invariants
- [ ] Orca runtime up; orchestration experimental on; `orchestration` skill loaded
- [ ] BASE ≠ DEFAULT_BRANCH (preflight)
- [ ] No in-process Task/subagent substitutes for Orca dispatch
- [ ] We **use** Orca orchestration — we do not replace it
- [ ] Coordinator does not vote in its own quorum
- [ ] JURY winner pick → human gate always (never auto-act, even if unanimous)

## Ballot (verbatim)
```
<paste the exact ballot body sent to voters>
```

## Fan-outs / denominator
| send # | --to | thread_id | recipients | notes |
|--------|------|-----------|------------|-------|
| 1 | | | | |

- **Denominator N** (sum of recipients across fan-outs):
- **Votes cast** (QID-echoed replies by deadline):
- **Silent** (no reply by T):

## Votes / replies
| voter | model | thread_id | vote (A\|B\|abstain) | confidence (1–5) | rationale (one line) | on-time? |
|-------|-------|-----------|----------------------|------------------|----------------------|----------|
| | | | | | | |

Late votes (noted, not counted):

## Reduction
| option | count | share of cast |
|--------|-------|---------------|
| A | | |
| B | | |
| abstain (excluded) | | |

Result: CONFIRMED `<option>` | NOT confirmed (tie / short quorum / refute default)

## Outcome / route
- Routed: acted | taste-gated → gate-steward | parked | human (JURY winner)
- decision_gate id (if any):
- Notes:

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
