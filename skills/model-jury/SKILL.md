---
name: model-jury
description: >-
  Multi-model Orca jury: same ticket implemented independently on different
  agents (e.g. codex vs claude) in isolated worktrees, dual-axis reviewed, then
  human gate to pick or merge. Use for high-stakes designs, "model jury", or
  comparing agent approaches. Expensive — use sparingly.
license: MIT
compatibility: >-
  Requires Orca + orchestration with multiple agent CLIs (codex, claude, …).
  Matt implement, tdd, code-review.
---

# Model-Jury

One ticket, **N independent implementations**, human picks.

## Process

1. Freeze ticket + acceptance criteria (no scope drift mid-jury).
2. For each model/agent `M`:
   - `worktree create --name jury-<ticket>-<M> --no-parent`
   - implement+tdd worker with **no access** to other jury worktrees
3. For each implementation: `review-matrix` axes (or dual code-review).
4. Coordinator comparison table: correctness, simplicity, test quality, standards.
5. `gate-create`: pick A / B / hybrid (human specifies merge rules).
6. Integrate winner onto BASE; archive losers (keep branches for audit).

## Rules

- No worker may read another jury branch.
- Same acceptance criteria for all.
- Cost warning up front (N× implement + N× review).

## Related

- `design-it-thrice` — design only, not full implement
- `matt-ship` — single-model default path
