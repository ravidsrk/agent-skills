---
name: architecture-sprint
description: >-
  Orchestrate codebase health deepening: Matt improve-codebase-architecture
  survey → human picks deepenings → optional design-it-thrice → grill-with-docs
  → to-tickets → implement fleet. Use for architecture sprints, agent-readability
  upkeep, or "deepen this module under Orca". Not a free-for-all refactor.
license: MIT
compatibility: >-
  Requires Orca + orchestration. Matt improve-codebase-architecture,
  codebase-design, grill-with-docs, to-tickets, implement. Optional design-it-thrice skill.
---

# Architecture-Sprint

Keep the codebase good for agents **without freelancing large refactors**.

## Phase graph

```
SURVEY (improve-codebase-architecture → HTML/report of deepenings)
  → HUMAN PICK 1–3 deepenings (gate)
  → optional DESIGN (design-it-thrice per pick)
  → ALIGN (grill-with-docs on chosen deepening)
  → TICKETS → IMPLEMENT FLEET (matt-ship phases from tickets)
  → REVIEW + integrate
```

## Rules

- Survey is **read-only** until human picks.
- Each deepening is a **vertical** ticket set, not “rewrite the world”.
- Wide mechanical renames: expand–contract batches (Matt to-tickets rules).
- Prefer deep modules (small interface, hidden complexity) over drive-by renames.

## Related

- `design-it-thrice` for interface exploration
- `matt-ship` for delivery after tickets
