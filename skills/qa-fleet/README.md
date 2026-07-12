# qa-fleet

<p align="center">
  <img src="assets/banner.jpg" alt="qa-fleet" width="100%">
</p>

Orchestrate gstack /qa and /qa-only under Orca: parallel browse axes against a staging URL, optional bounded auto-fix, re-verify.

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
ln -sfn "$(pwd)/agent-skills/skills/qa-fleet" ~/.claude/skills/qa-fleet

# gstack for workers (methodology):
git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
(cd ~/.claude/skills/gstack && ./setup)

orca status --json   # must be running
```

## Layout

`SKILL.md` · `scripts/` (spawn/preflight/pm) · `assets/` (preambles) · `references/ledger-template.md`

## Related

See `a mission sequence (AGENTS.md)` for end-to-end composition. Peers: `matt-ship`, `spec-to-ship`, `clean-sweep`.
