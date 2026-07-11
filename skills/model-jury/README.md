# model-jury

**Multi-model independent implement + pick gate.**

🟢 **Hard dependency:** Orca runtime + `orchestration` skill (from Orca CLI — not this repo) + [mattpocock/skills](https://github.com/mattpocock/skills) for worker playbooks.

# When to use

Triggers: *model jury*

# Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
ln -sfn "$(pwd)/agent-skills/skills/model-jury" ~/.claude/skills/model-jury
# Also install Matt skills for workers:
npx skills add mattpocock/skills -y
```

Shared helpers: [`scripts/orca-coord/`](../../scripts/orca-coord/).

# See also

- SKILL.md — full coordinator playbook
- Sibling orchestration skills in this repo (matt-ship, wayfinder-fleet, …)
- Peers: `spec-to-ship` (frozen greenfield), `clean-sweep` (audit close-out)
