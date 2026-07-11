---
name: ready-agent-drain
description: >-
  Drain tracker issues labeled ready-for-agent via Orca: claim, implement+tdd
  workers on the frontier, dual review, PR to integration BASE, capped
  concurrency. Use for "drain the agent queue", continuous ready-for-agent
  processing, or post-triage fleets. Does not triage (use triage-to-fleet first).
  Never auto-promotes to default branch without human gate.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI). Matt implement, tdd, code-review. Tracker with
  ready-for-agent label mapping from setup-matt-pocock-skills. git/gh.
---

# Ready-Agent-Drain

Pull **`ready-for-agent`** issues and run them as an AFK fleet.



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

## Preconditions

- Issues already triaged with agent briefs (from humans or `triage-to-fleet`).
- Integration `{{BASE}}` ≠ default; preflight OK.
- Concurrency cap agreed (default 3).

## Loop

```
while issues labeled ready-for-agent (bounded batch):
  claim (assignee) + task-create
  worktree + implement+tdd worker
  dual-axis review workers
  merge to BASE (commit-preserving)
  comment on issue with PR link; leave open until promotion policy says close
human gate: promotion PR BASE → default
```

## Rules

- Respect **Blocked-by** if present; skip blocked issues.
- Do not invent scope beyond the agent brief.
- On ambiguity: `escalation` / `decision_gate`, not silent guessing.
- Hot-file collisions → serialize merges.
- Cron/automation friendly: one batch per invocation; leave ledger for resume.

## Related

- `triage-to-fleet` — produces ready-for-agent
- `matt-ship` — greenfield idea path (not inbox)
