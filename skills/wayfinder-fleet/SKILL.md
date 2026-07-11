---
name: wayfinder-fleet
description: >-
  Orchestrate Matt /wayfinder on Orca: chart a shared decision map, clear AFK
  research/task frontier tickets in parallel workers, hold HITL grilling/prototype
  at decision gates, then for CODING hand off to /to-spec → /to-tickets →
  /implement (via matt-ship). Use when the user has foggy multi-session work,
  "wayfinder fleet", "chart the map and parallel research", or huge efforts too
  big for one session. Not the entire coding delivery path — after the map is
  complete, freeze a spec and fleet-implement (Matt v1.1+ clarification).
license: MIT
compatibility: >-
  Requires Orca + orchestration skill (Orca CLI). Matt skills: wayfinder,
  grilling, domain-modeling, research, prototype, handoff, to-spec, to-tickets,
  implement. git/gh/python3. Issue tracker configured via setup-matt-pocock-skills.
---

# Wayfinder-Fleet

Coordinate **`/wayfinder`** under Orca so unblocked **AFK** tickets run in parallel
while **HITL** tickets stay human-true.

## Matt’s clarification (coding vs content)

**For coding, the preferred flow is:**

```
/wayfinder  →  /to-spec  →  /to-tickets  →  /implement
```

Once the **map is complete** (way clear, no open decision tickets), you **turn it into a
spec** and hand implementation to AFK agents. Do **not** use wayfinder as the entire
coding path from grill → shipped product (v1.1 feedback).

Wayfinder *can* own the whole journey for **non-coding** work (e.g. course creation) —
see **`content-wayfinder`** for that path.

This skill **stops at map-complete for coding** and either:

1. Invokes / hands off to **`matt-ship`** at the to-spec phase, or  
2. Explicitly runs to-spec → to-tickets → implement fleet itself if the user asks to continue.

## Hard rules from /wayfinder

- **Plan, don’t do** (unless Notes override) — tickets resolve *decisions*, not product delivery.
- **Never resolve more than one ticket per session/worker.**
- **HITL tickets** (grilling, prototype): agent never answers for the human.
- **AFK tickets** (research, some tasks): safe to parallelize on Orca.
- Claim tickets (assignee) **before** work so concurrent sessions don’t collide.

## Phase graph

```
SELF-ORIENT (tracker, labels)
  → CHART map (HITL: grilling + domain-modeling)  — one session, no resolve
  → LOOP:
       load map → frontier (open, unblocked, unclaimed)
       partition AFK vs HITL
       AFK: parallel Orca workers (research/task) → resolution comments → close
       HITL: decision_gate / human session → resolve one at a time
       graduate fog → new tickets + deps
  → MAP COMPLETE?
       coding  → FREEZE narrative → /to-spec → (matt-ship or to-tickets+implement)
       content → continue in content-wayfinder or stay in map if user wants
```

## Chart the map (HITL, coordinator)

1. Name **Destination** via `/grilling` + `/domain-modeling`.
2. Breadth-first grill for open decisions.
3. Create map issue (`wayfinder:map`) + child tickets with `wayfinder:research|prototype|grilling|task`.
4. Wire blocking edges (second pass).
5. **Stop** — charting session does not also resolve tickets.

## Work the map (fleet loop)

### AFK wave

For each frontier `research` / AFK `task`:

```text
task-create --spec "Resolve wayfinder ticket <name>: <question>. Write resolution comment + asset path. Close issue. worker_done."
worktree optional (research can be same-repo scratch)
dispatch --inject → check --wait worker_done
verify issue closed + map Decisions-so-far pointer updated
```

### HITL

- `grilling` / `prototype`: create `gate-create` or pause for human session; **never** auto-complete.
- Prototype: supervised worktree with `/prototype`; human reacts; record answer.

### Fog

Graduate **Not yet specified** only when questions are sharp; never pre-slice coarse fog into fake tickets.

## Map complete → coding handoff

When no open in-scope tickets remain and destination is clear:

1. Write a short **map complete** summary (decisions index + links).
2. Run **`/to-spec`** synthesizing the map (not re-grilling the world).
3. Human freeze.
4. **`/to-tickets`** → Orca DAG → **`/implement`** fleet  
   Prefer loading **`matt-ship`** from Phase “SPEC” onward so one skill owns ship discipline.

## Related

- `matt-ship` — coding delivery after to-spec.
- `content-wayfinder` — non-coding full journey inside wayfinder.
- `research-then-grill` — evidence pack *before* charting.
