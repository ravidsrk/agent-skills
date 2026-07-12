# matt-ship

<p align="center">
  <img src="assets/banner.jpg" alt="matt-ship" width="100%">
</p>

Coordinate Matt’s main engineering flow on **Orca**: grill-with-docs → to-spec → to-tickets → parallel implement(+tdd) → dual-axis review → PR.

## Hard base: Orca (we use it — we don’t replace it)

| Need | Source |
|------|--------|
| Runtime + task/dispatch/`worker_done` | **Orca** |
| Command grammar / lifecycle | **`orchestration` skill (Orca CLI)** — not this repo |
| This playbook | `SKILL.md` in this folder |
| Worker playbooks | [mattpocock/skills](https://github.com/mattpocock/skills) |

If Orca is down or orchestration experimental is off, **stop** — do not fake multi-agent with subagents.

## When to use

*idea to ship, AFK fleet implement, matt ship*

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
ln -sfn "$(pwd)/skills/matt-ship" ~/.claude/skills/matt-ship

# Workers need Matt skills:
npx skills add mattpocock/skills -y

# Orca: install app/CLI, enable orchestration experimental, ensure `orchestration` skill is available
orca status --json
```

## Layout

```
matt-ship/
├── SKILL.md
├── README.md
├── scripts/          # spawn_worker (calls Orca) · preflight (git/gh) · pm (JSON parser)
├── assets/           # role preambles
└── references/       # ledger template + skill-specific refs
```

## Related

wayfinder-fleet (if foggy first), review-matrix

Also: `spec-to-ship` / `clean-sweep` (Orca peers, not Matt-based).
