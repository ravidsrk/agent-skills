---
name: research-then-grill
description: >-
  Parallel evidence gathering before HITL grilling: Orca workers run Matt
  /research and/or monid deep-research, join a cited research pack, then
  coordinator runs grill-with-docs that must ground questions in the pack.
  Use when "research then grill", pre-flight evidence before design, or
  avoiding vibe-based planning. Research is input — never a substitute for
  grilling or a drafted product decision.
license: MIT
compatibility: >-
  Requires Orca + orchestration. Matt research and/or agent-skills deep-research
  (monid). grill-with-docs for the HITL phase. MONID_API_KEY if monid path used.
---

# Research-Then-Grill

**Evidence first, interview second.**

## Process

### 1. Frame the decision

One sentence: what decision will this research inform?

### 2. Parallel research workers

| Worker | Tool | Output |
|--------|------|--------|
| Primary sources | Matt `/research` | `research/<slug>.md` cited |
| Discourse pack | monid `deep-research` | `research/<slug>/research-*.{md,json}` |

Dispatch 1–N workers with non-overlapping source mandates. `worker_done` requires `reportPath`.

### 3. Join pack (coordinator)

Write `research/<slug>/PACK.md`:

- Decision question
- Convergences across sources
- Contradictions
- Gaps
- Links to raw dumps (**no editorial “bottom line” product decision**)

### 4. Grill (HITL, coordinator)

Run `/grill-with-docs`. Rules for this phase:

- Every major question should **reference PACK.md** (or admit gap).
- Do not invent market facts that research didn’t support.
- Update CONTEXT.md/ADRs as usual.

### 5. Exit

Hand to `wayfinder-fleet` (if still foggy) or `matt-ship` / `/to-spec`.

## Anti-patterns

- Research worker that writes the product plan
- Grilling that ignores the pack
- Single-source research called “deep”
