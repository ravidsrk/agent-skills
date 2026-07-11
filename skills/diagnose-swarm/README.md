# diagnose-swarm

<p align="center">
  <img src="assets/banner.jpg" alt="diagnose-swarm" width="100%">
</p>

Hard-bug swarm: repro (red command) → fix+tdd → dual review on Orca.

## Hard base: Orca (we use it — we don’t replace it)

| Need | Source |
|------|--------|
| Runtime + task/dispatch/`worker_done` | **Orca** |
| Command grammar / lifecycle | **`orchestration` skill (Orca CLI)** — not this repo |
| This playbook | `SKILL.md` in this folder |
| Worker playbooks | [mattpocock/skills](https://github.com/mattpocock/skills) |

If Orca is down or orchestration experimental is off, **stop** — do not fake multi-agent with subagents.

## When to use

*diagnose swarm, flake, intermittent bug*

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
ln -sfn "$(pwd)/skills/diagnose-swarm" ~/.claude/skills/diagnose-swarm

# Workers need Matt skills:
npx skills add mattpocock/skills -y

# Orca: install app/CLI, enable orchestration experimental, ensure `orchestration` skill is available
orca status --json
```

## Layout

```
diagnose-swarm/
├── SKILL.md
├── README.md
├── scripts/          # spawn_worker, preflight, pm (call Orca)
├── assets/           # role preambles
└── references/       # ledger template + skill-specific refs
```

## Related

review-matrix, architecture-sprint

Also: `spec-to-ship` / `clean-sweep` (Orca peers, not Matt-based).
