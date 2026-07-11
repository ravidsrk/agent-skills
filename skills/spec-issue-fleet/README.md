# spec-issue-fleet

<p align="center">
  <img src="assets/banner.jpg" alt="spec-issue-fleet" width="100%">
</p>

Orchestrate gstack /spec into a GitHub issue then Orca worktree implement fleet.

## Hard base: Orca (we use it — we do not replace it)

| Need | Source |
|------|--------|
| Runtime + dispatch + `worker_done` | **Orca** |
| Command grammar | **`orchestration` skill (Orca CLI)** |
| This playbook | `SKILL.md` |
| Worker methodology | [garrytan/gstack](https://github.com/garrytan/gstack) (+ Matt skills where noted) |

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
ln -sfn "$(pwd)/agent-skills/skills/spec-issue-fleet" ~/.claude/skills/spec-issue-fleet

# gstack for workers (methodology):
git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
(cd ~/.claude/skills/gstack && ./setup)

orca status --json   # must be running
```

## Layout

`SKILL.md` · `scripts/` (spawn/preflight/pm) · `assets/` (preambles) · `references/ledger-template.md`

## Related

See `full-sprint-fleet` for end-to-end composition. Peers: `matt-ship`, `spec-to-ship`, `clean-sweep`.
