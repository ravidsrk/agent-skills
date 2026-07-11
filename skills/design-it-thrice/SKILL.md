---
name: design-it-thrice
description: >-
  Orca-native "design it twice/thrice": spawn 3+ isolated worktree workers that each
  produce a radically different module interface design using Matt codebase-design
  vocabulary, then compare on depth/locality/seams and gate a human pick. Use when
  designing an API, exploring interface options, "design it thrice", or comparing
  module shapes. Replaces in-process parallel subagents with true Orca isolation.
license: MIT
compatibility: >-
  Requires Orca + orchestration (Orca CLI). Matt skills: codebase-design (and optionally
  domain-modeling, prototype). codex/claude workers; git.
---

# Design-It-Thrice

You are the coordinator. **Workers design; you compare; human picks.**

## Why Orca

In-process subagents share residual context and drift toward similar designs. Each worker
gets a **fresh terminal + isolated worktree** and a **radical constraint** that forbids
converging on the same shape.

## Process

### 1. Frame (coordinator)

- Name the module / seam / problem.
- Load domain glossary if present.
- Pick ≥3 radical poles (examples):
  - **Minimal surface** — fewest operations that still close the use cases
  - **Event / capability ports** — explicit commands + handlers
  - **Data-first / schema-centric** — types and invariants as the interface
  - **Pass-the-baton pipeline** — pure stages, no god object
  - **Facade over existing mess** — deep module in front of legacy

### 2. Fan-out (AFK workers)

For each pole `P`:

```text
task-create --spec "
Use /codebase-design vocabulary. Design a RADICALLY DIFFERENT interface for <module>
under constraint: <P>. Output:
1) public interface sketch (types/functions only)
2) depth argument (what complexity is hidden)
3) seams/adapters
4) failure modes
5) why this is NOT the same as the other poles
Write to design/<slug>-<P>.md. Do NOT implement production code. worker_done with reportPath.
"
worktree create --name design-<P> --no-parent
dispatch --inject
```

Cap concurrent designers at 3–5. Enforce **radical difference** in the prompt (list the other poles and ban their signatures).

### 3. Join + compare (coordinator)

Build a comparison table:

| Pole | Interface size | Depth | Locality | Seam quality | Risks |
|------|----------------|-------|----------|--------------|-------|

Do **not** pick a winner for the human unless they asked you to recommend with ranked rationale.

### 4. Gate

`gate-create`: human selects winner (or hybrid with explicit merge rules).

### 5. Optional follow-through

- Thin prototype of winner (`/prototype` worker)
- Or hand to `matt-ship` / `/grill-with-docs` → tickets for implementation

## Anti-patterns

- Three workers producing the same CRUD service with different names
- Coordinator rewriting designs mid-flight
- Implementing the chosen design inside a design worktree without a new ticket
