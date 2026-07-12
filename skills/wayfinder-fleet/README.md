# wayfinder-fleet

<p align="center">
  <img src="assets/banner.jpg" alt="wayfinder-fleet" width="100%">
</p>

Orchestrate `/wayfinder` on Orca. AFK research in parallel; HITL stays human. **Coding:** map complete → `/to-spec` → tickets → implement (Matt v1.1+).

## Hard base: Orca (we use it — we don’t replace it)

| Need | Source |
|------|--------|
| Runtime + task/dispatch/`worker_done` | **Orca** |
| Command grammar / lifecycle | **`orchestration` skill (Orca CLI)** — not this repo |
| This playbook | `SKILL.md` in this folder |
| Worker playbooks | [mattpocock/skills](https://github.com/mattpocock/skills) |

If Orca is down or orchestration experimental is off, **stop** — do not fake multi-agent with subagents.

## When to use

*wayfinder fleet, foggy multi-session map*

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
ln -sfn "$(pwd)/skills/wayfinder-fleet" ~/.claude/skills/wayfinder-fleet

# Workers need Matt skills:
npx skills add mattpocock/skills -y

# Orca: install app/CLI, enable orchestration experimental, ensure `orchestration` skill is available
orca status --json
```

## Layout

```
wayfinder-fleet/
├── SKILL.md
├── README.md
├── scripts/          # spawn_worker (calls Orca) · preflight (git/gh) · pm (JSON parser)
├── assets/           # role preambles
└── references/       # ledger template + skill-specific refs
```

## Related

matt-ship, wayfinder-fleet, research-then-grill

Also: `spec-to-ship` / `clean-sweep` (Orca peers, not Matt-based).
