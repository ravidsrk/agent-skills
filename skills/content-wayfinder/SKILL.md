---
name: content-wayfinder
description: >-
  Non-coding wayfinder orchestration (courses, curricula, long-form content):
  keep the journey inside the map — research, outline grilling, prototypes of
  lessons, writing workers — without forcing /to-spec → implement. Use for course
  creation, content programs, or when Matt notes wayfinder as the whole flow for
  non-coding. For software features, use wayfinder-fleet then matt-ship instead.
license: MIT
compatibility: >-
  Requires Orca + orchestration. Matt wayfinder, grilling, research, writing-*
  skills if present; scaffold-exercises optional.
---

# Content-Wayfinder

Matt’s note: wayfinder **can** be the entire flow for **non-coding** work (e.g. course
creation). This skill is that path under Orca.

## Contrast with coding

| | Coding | Content (this skill) |
|--|--------|----------------------|
| After map clear | `/to-spec` → tickets → AFK implement | Keep producing content artifacts on the map |
| Destination | Spec / shipped feature | Published module / lesson set / outline |
| AFK workers | implement+tdd | research, exercise scaffold, draft sections |

## Phase graph

```
CHART map (destination = ship content X)
  → LOOP frontier:
       research (parallel)
       grilling (HITL outlines)
       prototype (sample lesson / exercise)
       task (assets, recordings checklist)
  → optional writing workers (shape/beats/fragments if installed)
  → DONE when destination content exists and is linked from map
```

## Rules

- Still **one ticket per worker session**.
- HITL never self-answered.
- Prefer durable assets in-repo (`content/`, `course/`) linked from tickets.
- Do **not** auto-route to `matt-ship` unless the user pivots to software.

## Related

- `wayfinder-fleet` — coding-oriented wayfinder that exits to to-spec
