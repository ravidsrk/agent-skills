# Shared Orca coordinator helpers

Used by Matt×Orca orchestration skills (`matt-ship`, `wayfinder-fleet`, …).

| File | Purpose |
|---|---|
| `spawn_worker.sh` | Reliable `terminal create` → settle → `dispatch --inject` → Enter (claude) |
| `preflight.py` | BASE ≠ default branch, git/gh present, BASE forks from default |
| `pm.py` | Tolerant parser for orchestration inbox/check JSON |

## Hard dependencies

- **Orca runtime** running (`orca status --json`)
- Experimental **orchestration** enabled
- Companion **`orchestration` skill from the Orca CLI** (not this repo)
- Worker CLIs: `codex`, `claude` (as needed)
- Matt skills installed for worker prompts (`npx skills add mattpocock/skills`)

## Conventions all coordinator skills share

1. Coordinator is **thin** — never implements, never dual-role reviews.
2. HITL skills (`grill-*`, domain-modeling, triage state apply) stay on the **coordinator terminal**.
3. AFK work (`implement`, research, dual review, prototype) is **dispatched** to workers.
4. Matt **Blocked-by** edges → Orca `task-create --deps`.
5. One ticket ≈ one worktree ≈ one dispatch (clear context).
6. Full ownership handoff uses **`orca-cli`**, not `dispatch --inject`.
7. Verify merges: `state=MERGED` + `baseRefName==BASE` + change greppable on base.

## Coding main flow (Matt v1.1+ clarification)

```
/wayfinder → /to-spec → /to-tickets → /implement   # coding (prefer AFK implement)
```

Do **not** treat wayfinder as the entire coding delivery path. After the map is complete, freeze a **spec**, ticket it, then fleet implement.

Non-coding (course content, etc.) may keep work inside wayfinder / content-wayfinder.
