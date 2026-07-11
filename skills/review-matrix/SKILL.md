---
name: review-matrix
description: >-
  Orca review wall on a PR or branch: parallel build-blind workers for Matt
  code-review Standards axis, Spec axis, optional security/hygiene, and
  test-adequacy (would tests fail if the fix were reverted?). Use when
  reviewing a PR, "review matrix", dual-axis review under orchestration, or
  pre-merge quality wall. Coordinator aggregates; never merges axes.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt code-review skill. git; optional gitleaks
  and PR review bot. Spec source (issue/PRD) when Spec axis runs.
---

# Review-Matrix

Coordinate a **multi-axis review** with true isolation. Axes stay separate in the final report.



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

## Inputs

- Fixed point (`main`, tag, SHA) or PR number
- Spec source (issue, PRD path) — Spec axis skips if none
- Optional axes: security-lite, test-adequacy

## Axes (default)

| Axis | Worker brief |
|------|----------------|
| **Standards** | Matt `/code-review` Standards only (repo standards + smell baseline) |
| **Spec** | Matt `/code-review` Spec only against originating issue/PRD |
| **Security-lite** (opt) | Secrets, authz/tenant checks, dangerous defaults in the diff |
| **Test-adequacy** (opt) | For each claimed fix: would removing the production change fail a test? |

## Process

1. Pin fixed point; ensure non-empty `git diff <fp>...HEAD`.
2. Create **fresh terminals** (same worktree OK; **fresh sessions** mandatory). Never use the author terminal.
3. `task-create` one task per axis (no deps between axes) → `dispatch --inject` in parallel.
4. `check --wait` until all `worker_done` (or timeout → liveness check, don’t kill slow reviewers).
5. Aggregate under separate headings; **do not rerank across axes**.
6. Gate: human decide merge / fix tasks.

## Output template

```markdown
## Standards
…

## Spec
…

## Security-lite (if run)
…

## Test-adequacy (if run)
…

## Summary
Standards: N findings (worst: …)
Spec: N findings (worst: …)
```

## Related

- Embedded after each ticket in **`matt-ship`**
- **`adversarial-ticket`** for refuse-surface attacks beyond review
