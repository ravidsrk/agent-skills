# adversarial-ticket

<p align="center">
  <img src="assets/banner.jpg" alt="adversarial-ticket" width="100%">
</p>

Red-team ticket acceptance after implement; fix P0 + ratchet; re-review.

## Hard base: Orca (we use it — we don’t replace it)

| Need | Source |
|------|--------|
| Runtime + task/dispatch/`worker_done` | **Orca** |
| Command grammar / lifecycle | **`orchestration` skill (Orca CLI)** — not this repo |
| This playbook | `SKILL.md` in this folder |
| Worker playbooks | [mattpocock/skills](https://github.com/mattpocock/skills) |

If Orca is down or orchestration experimental is off, **stop** — do not fake multi-agent with subagents.

## When to use

*adversarial ticket, refuse surface*

## Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
ln -sfn "$(pwd)/skills/adversarial-ticket" ~/.claude/skills/adversarial-ticket

# Workers need Matt skills:
npx skills add mattpocock/skills -y

# Orca: install app/CLI, enable orchestration experimental, ensure `orchestration` skill is available
orca status --json
```

## Layout

```
adversarial-ticket/
├── SKILL.md
├── README.md
├── scripts/          # spawn_worker, preflight, pm (call Orca)
├── assets/           # role preambles
└── references/       # ledger template + skill-specific refs
```

## Related

review-matrix

Also: `spec-to-ship` / `clean-sweep` (Orca peers, not Matt-based).
