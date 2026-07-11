---
name: model-jury
description: >-
  Multi-model Orca jury: same ticket implemented independently on different
  agents (e.g. codex vs claude) in isolated worktrees, dual-axis reviewed, then
  human gate to pick or merge. Use for high-stakes designs, "model jury", or
  comparing agent approaches. Expensive — use sparingly.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI) with multiple agent CLIs (codex, claude, …).
  Matt implement, tdd, code-review.
---

# Model-Jury

One ticket, **N independent implementations**, human picks.



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
