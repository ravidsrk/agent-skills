# Model-jury — pick / merge rules

## When NOT to use
- Routine tickets (use single-model `matt-ship`)
- HITL grilling / design interviews
- Cost-sensitive runs (N× implement + N× review)

## Pick rules (default)
1. **Correctness first** — fails acceptance criteria → eliminated  
2. **Test quality** — real regression tests beat coverage theater  
3. **Simplicity** — smaller diff / clearer module boundary wins ties  
4. **Standards** — documented repo standards beat style bikesheds  

## Hybrid merge (only if human explicitly chooses hybrid)
Allowed hybrids:
- Take **A’s public interface** + **B’s tests** (if tests map cleanly)
- Take **A’s core logic** + **B’s adapter** only when seams match

Forbidden hybrids:
- Cherry-pick random files from both without a seam map
- Mixing both full trees into one branch (guaranteed conflict soup)

Process for hybrid:
1. Human writes hybrid rule in one sentence on the gate resolution  
2. Fresh **integrator** worker implements hybrid from scratch against BASE  
3. Full review-matrix on hybrid  
4. Archive loser branches; do not delete until promotion  

## Output
Record winner + rationale in the ledger and on the ticket/PR.
