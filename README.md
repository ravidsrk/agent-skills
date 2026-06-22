# agent-skills

Public Agent Skills by [@ravidsrk](https://github.com/ravidsrk), built to the [agentskills.io](https://agentskills.io/specification) specification.

These skills are open-source, MIT-licensed, and work in any agent runtime that supports the Agent Skills spec — Claude Code, Cursor, OpenClaw, Codex, Augment, and others.

# Skills in this repo

| Skill | Description | Cost / use |
|---|---|---|
| [`terminal-poster`](skills/terminal-poster/) | Generate dense, retro-cyberpunk infographic posters in a terminal-aesthetic style. Five reusable templates (Cluster A–E). [See live examples](skills/terminal-poster/README.md#live-examples). Uses Nano Banana Pro via OpenRouter. | ~$0.002 + ~30s per image |
| [`deep-research`](skills/deep-research/) | Parallel multi-source research orchestrator. Fans out across 8 sources (X, Reddit, HN, GitHub repos + issues, Polymarket, YouTube w/ transcripts, Exa) via [monid](https://monid.dev) and dumps structured + human-readable evidence. One auth, one balance. | ~$0.10–0.20 + ~60–90s per run |

# Preview

<a href="skills/terminal-poster/README.md#live-examples">
  <img src="skills/terminal-poster/assets/examples/cluster-c2-walkbot.jpg" alt="Cluster C2 example — WalkBot" width="280">
  <img src="skills/terminal-poster/assets/examples/cluster-a-stack.png" alt="Cluster A example — agent stack" width="280">
  <img src="skills/terminal-poster/assets/examples/cluster-b-maturity.png" alt="Cluster B example — maturity ladder" width="280">
</a>

Three real first-generation outputs from `terminal-poster`. [Audit scores + how-to-reproduce →](skills/terminal-poster/README.md#live-examples)

# Quick start

# 1. Clone the repo

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
```

# 2. Install a skill into your agent runtime

Most runtimes look for skills in a configured directory. Symlink (or copy) the skill there:

**Claude Code / VS Code / generic:**

```bash
# Adjust the destination path to your runtime's skill directory
ln -s "$(pwd)/skills/terminal-poster" ~/.claude/skills/terminal-poster
```

**Mogra:**

```bash
ln -s "$(pwd)/skills/terminal-poster" /workspace/.mogra/skills/terminal-poster
```

The next time your agent starts, it'll discover the skill.

# 3. Use it

Each skill's `SKILL.md` has its own activation triggers (in the `description` field) and instructions. The agent will pick up the skill automatically when you ask for what it does — e.g. for `terminal-poster`:

> "Make this look like a viral X post"
> "Generate a Shann-style infographic for my product"
> "Create a terminal-aesthetic poster for our agent stack"

# Repo layout

```
agent-skills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── scripts/
│   └── validate-skills.py    ← Validates every SKILL.md against agentskills.io spec
└── skills/
    ├── terminal-poster/
    │   ├── SKILL.md
    │   ├── scripts/
    │   ├── references/
    │   └── assets/
    └── deep-research/
        ├── SKILL.md
        ├── README.md
        └── scripts/
            ├── research.py
            └── sources/
```

Every skill is a directory under `skills/` containing at minimum a `SKILL.md` with frontmatter. See the [Agent Skills specification](https://agentskills.io/specification) for the format.

# Validation

Run the validator to check every skill is spec-compliant before committing:

```bash
python3 scripts/validate-skills.py
```

The validator enforces:
- `name`: 1–64 chars, lowercase letters/digits/hyphens, matches folder name
- `description`: 1–1024 chars
- `compatibility`: 1–500 chars (if present)

# Contributing

PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the rules.

# License

MIT. See [LICENSE](LICENSE).

# Credits

- `terminal-poster` — visual pattern reverse-engineered from public posts by [@shannholmberg](https://x.com/shannholmberg) on X. The skill makes the look reproducible across topics; Shann designed the look itself.
- `deep-research` — originally inspired by [`mvanhorn/last30days-skill`](https://github.com/mvanhorn/last30days-skill). The 30-day default window came from that upstream; the 8-source fan-out and monid routing were rebuilt from scratch.
