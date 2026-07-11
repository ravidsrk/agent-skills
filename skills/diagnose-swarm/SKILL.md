---
name: diagnose-swarm
description: >-
  Multi-role Orca swarm for hard bugs using Matt diagnosing-bugs: repro worker
  raises flake rate, optional bisect worker, fix+/tdd worker, dual-axis review.
  Use when "diagnose swarm", intermittent bugs, regressions between known-good
  states, or bugs that resist first-glance fixes. Coordinator holds the tight
  feedback-loop invariant — no theorising without a red command.
license: MIT
compatibility: >-
  Requires Orca + orchestration. Matt diagnosing-bugs, tdd, code-review;
  optionally improve-codebase-architecture. git; test runner.
---

# Diagnose-Swarm

Hard bugs need a **tight red command** before any theory. Roles:

| Role | Skill / duty | Deps |
|------|----------------|------|
| **A Repro** | `/diagnosing-bugs` loop: raise reproduction rate; one command that goes red | — |
| **B Bisect** (opt) | Timeline / git bisect once red command exists | A |
| **C Fix** | `/tdd` regression first, then fix | A |
| **D Review** | Dual-axis `/code-review` | C |
| **E Seam** (opt) | `/improve-codebase-architecture` if “no good seam to lock the bug” | D or human |

## Invariants

1. **No fix worker until A delivers a red command** (path + args in `worker_done`).
2. Fix worker must add a **regression test that fails if the fix is reverted**.
3. Build-blind review (D ≠ C).
4. Flakes: raise rate; don’t “retry until green” and call it fixed.

## Process

1. Orient: pin last-good / first-bad if known; capture env.
2. Dispatch **A** in a worktree (or same tree if needs local state).
3. On A done: gate human if repro is environmental; else dispatch B (optional) + C.
4. C → D review matrix axes.
5. If architecture is the real finding: E or hand to `architecture-sprint`.

## Related

- Single-session path: Matt `/diagnosing-bugs` alone (no Orca)
- `review-matrix` for the D phase alone
