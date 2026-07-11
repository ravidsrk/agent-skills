# Architecture-sprint rules

## Survey is read-only
`/improve-codebase-architecture` produces candidates. **No refactors until human picks.**

## Pick 1–3 deepenings max
More than three in one sprint → thrash. Backlog the rest.

## Each deepening becomes vertical tickets
Not “rewrite package X.” Prefer:
1. Introduce deep module at a seam  
2. Move one caller path behind it  
3. Delete old path when unused  

Wide renames: expand → migrate batches → contract (Matt to-tickets rules).

## Optional design-it-thrice
Only when the interface is load-bearing and ambiguous. Skip for mechanical deepenings.

## Exit
Tickets → implement fleet via `matt-ship` phases (or dispatch implement workers with same rules). Always Orca orchestration for AFK work.
