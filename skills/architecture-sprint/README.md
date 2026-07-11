# architecture-sprint

<p align="center">
  <img src="assets/banner.jpg" alt="architecture-sprint" width="100%">
</p>

Deepening survey → human pick → optional design-it-thrice → tickets → implement fleet.

## Hard base: Orca (we use it — we don’t replace it)

| Need | Source |
|------|--------|
| Runtime + task/dispatch/`worker_done` | **Orca** |
| Command grammar / lifecycle | **`orchestration` skill (Orca CLI)** — not this repo |
| This playbook | `SKILL.md` in this folder |
| Worker playbooks | [mattpocock/skills](https://github.com/mattpocock/skills) |

If Orca is down or orchestration experimental is off, **stop** — do not fake multi-agent with subagents.

## When to use

*architecture sprint, deepen modules*

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
ln -sfn "$(pwd)/skills/architecture-sprint" ~/.claude/skills/architecture-sprint

# Workers need Matt skills:
npx skills add mattpocock/skills -y

# Orca: install app/CLI, enable orchestration experimental, ensure `orchestration` skill is available
orca status --json
```

## Layout

```
architecture-sprint/
├── SKILL.md
├── README.md
├── scripts/          # spawn_worker, preflight, pm (call Orca)
├── assets/           # role preambles
└── references/       # ledger template + skill-specific refs
```

## Related

design-it-thrice, matt-ship

Also: `spec-to-ship` / `clean-sweep` (Orca peers, not Matt-based).
