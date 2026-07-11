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
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt implement/tdd/code-review vocabulary.
  Test runner; optional e2e harness.
---

# Adversarial-Ticket

Green tests ≠ safe. Attack the ticket’s invariants.



## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — not on other skills in this pack, and not on in-process subagents.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca (`orca orchestration …`) |
| **Grammar** | CLI + lifecycle rules | **`orchestration` skill from the Orca CLI** (not this repo) |
| **This skill** | *what / when / why* on top of that grammar | this repo |
| **Workers** | AFK playbooks (Matt `/implement`, `/tdd`, …) | mattpocock/skills or this pack |

**Preflight (stop if any fail):** `orca status --json` running · orchestration experimental on · `orchestration` skill loaded · never substitute Task/subagent tools for `task-create` + `dispatch`.

**Full handoff** ("give this to another agent") → `orca-cli`, not supervised `dispatch --inject`, unless the user asked to supervise / wait for `worker_done`.

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
