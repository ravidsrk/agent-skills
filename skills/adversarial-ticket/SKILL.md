---
name: adversarial-ticket
description: >-
  After an implement worker_done, dispatch a build-blind red-team worker that
  attacks ticket acceptance criteria (authz, refuse surfaces, edge cases), then
  fix+ratchet if P0, then re-review. Use for "adversarial ticket", high-risk
  auth/tenant work, or when green unit tests are not enough. Complements
  review-matrix with active attack, not only reading the diff.
license: MIT
compatibility: >-
  Requires Orca + orchestration. Matt implement/tdd/code-review vocabulary.
  Test runner; optional e2e harness.
---

# Adversarial-Ticket

Green tests ≠ safe. Attack the ticket’s invariants.

## Pipeline

```
implement worker_done
  → RED-TEAM worker (fresh session, build-blind)
       tries to break acceptance criteria; writes failing tests or repros
  → if P0: FIX worker (deps=red-team) + ratchet (red-by-revert)
  → dual-axis REVIEW
  → merge
```

## Red-team brief (template)

```text
You did NOT implement this ticket. Attack it.
Ticket: <title + acceptance criteria>
Diff: <fp>...HEAD on branch
For each criterion: attempt a counterexample (cross-tenant, path traversal,
smuggled labels, TOCTOU, missing authz, hollow persistence).
Output: findings ranked P0/P1/P2 with repro steps or failing test paths.
Do not fix. worker_done.
```

## Triage

| Severity | Action |
|----------|--------|
| P0 | Fix in-branch before merge; audit whole class |
| P1 | Fix or explicit backlog with owner |
| P2 | Backlog |

## Related

- `review-matrix` — passive dual-axis read
- `spec-to-ship` adversarial phase — whole-product analogue
- `clean-sweep` — backlog of many findings
