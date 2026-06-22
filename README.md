<h1 align="center">agent-skills</h1>

<p align="center">
  <strong>Open-source Agent Skills you can drop into any spec-compliant runtime.</strong><br/>
  Built to the <a href="https://agentskills.io/specification">agentskills.io</a> specification.
</p>

<p align="center">
  <a href="https://github.com/ravidsrk/agent-skills/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://agentskills.io/specification"><img src="https://img.shields.io/badge/spec-agentskills.io-orange.svg" alt="agentskills.io spec"></a>
  <a href="https://github.com/ravidsrk/agent-skills/stargazers"><img src="https://img.shields.io/github/stars/ravidsrk/agent-skills.svg?style=flat" alt="Stars"></a>
  <a href="https://github.com/ravidsrk/agent-skills/commits/main"><img src="https://img.shields.io/github/last-commit/ravidsrk/agent-skills.svg" alt="Last commit"></a>
</p>

---

# What are Agent Skills?

**Agent Skills** are portable, self-contained capabilities you give an agent — each one is just a folder with a `SKILL.md` manifest. The agent reads the description, decides when to use it, and follows the instructions inside.

This repo collects skills I've built and battle-tested in production. Every skill here is:

- 🟢 **Spec-compliant** — validates against [agentskills.io](https://agentskills.io/specification)
- 🟢 **Runtime-agnostic** — works in Claude Code, Cursor, OpenClaw, Codex, Augment, Mogra, or any runtime that reads the spec
- 🟢 **Production-tested** — these aren't toys; they're the actual tools I use daily
- 🟢 **MIT-licensed** — fork, modify, ship

---

# Skills

| Skill | What it does | Trigger phrases | Cost / latency |
|---|---|---|---|
| 🎨 **[`terminal-poster`](skills/terminal-poster/)** | Generates dense, retro-cyberpunk infographic posters in a terminal aesthetic — pixel-bitmap headlines, ASCII box-drawing, monospace fonts. Five reusable templates (Cluster A–E). | *"Make this look like a viral X post"*, *"Shann-style infographic"*, *"terminal poster"* | ~$0.002 + ~30s per image |
| 🔍 **[`deep-research`](skills/deep-research/)** | Parallel multi-source research orchestrator. Fans out across **8 sources** (X, Reddit, HN, GitHub repos + issues, Polymarket, YouTube w/ transcripts, Exa) via [monid](https://monid.dev). One auth, one balance, structured + human-readable evidence dumps. | *"do a deep dive on X"*, *"what's the discourse on Y"*, *"research this topic"* | ~$0.10–0.20 + ~60–90s per run |

# Preview

<a href="skills/terminal-poster/README.md#live-examples">
  <img src="skills/terminal-poster/assets/examples/cluster-c2-walkbot.jpg" alt="Cluster C2 example — WalkBot" width="270">
  <img src="skills/terminal-poster/assets/examples/cluster-a-stack.png" alt="Cluster A example — agent stack" width="270">
  <img src="skills/terminal-poster/assets/examples/cluster-b-maturity.png" alt="Cluster B example — maturity ladder" width="270">
</a>

Three real first-generation outputs from `terminal-poster`. [Audit scores + how to reproduce →](skills/terminal-poster/README.md#live-examples)

---

# Quick start

# 1. Clone the repo

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
```

# 2. Install a skill into your agent runtime

Most runtimes look for skills in a configured directory. Symlink (or copy) the skill in:

| Runtime | Install path |
|---|---|
| **Claude Code** | `~/.claude/skills/<skill-name>` |
| **Cursor** | `~/.cursor/skills/<skill-name>` |
| **OpenClaw** | `~/.openclaw/skills/<skill-name>` |
| **Codex CLI** | `~/.codex/skills/<skill-name>` |
| **Mogra** | `/workspace/.mogra/skills/<skill-name>` |
| **Any runtime** | Wherever the runtime is configured to scan for skills |

**Example (Claude Code, `terminal-poster`):**

```bash
ln -s "$(pwd)/skills/terminal-poster" ~/.claude/skills/terminal-poster
```

**Example (Mogra, `deep-research`):**

```bash
ln -s "$(pwd)/skills/deep-research" /workspace/.mogra/skills/deep-research
```

Symlinking is recommended over copying — `git pull` will keep the skill up to date automatically.

# 3. Set any required env vars

Each skill's `README.md` lists what it needs. Common ones:

```bash
# terminal-poster — image generation
export OPENROUTER_API_KEY=...

# deep-research — multi-source research
export MONID_API_KEY=...
```

# 4. Use it

Skills auto-activate based on the `description` field in their `SKILL.md`. Just ask the agent for what you want — it'll discover the right skill and follow its instructions.

> 💬 *"Generate a terminal-style poster for our agent stack"* → activates `terminal-poster`
>
> 💬 *"Do a deep dive on agent harness engineering"* → activates `deep-research`

---

# Repo layout

```
agent-skills/
├── README.md                    ← You are here
├── LICENSE                      ← MIT
├── CONTRIBUTING.md              ← How to add a skill
├── scripts/
│   └── validate-skills.py       ← Validates SKILL.md against agentskills.io spec
└── skills/
    ├── terminal-poster/
    │   ├── SKILL.md             ← Manifest (frontmatter + instructions)
    │   ├── README.md            ← Human docs, examples, prompt library
    │   ├── scripts/             ← Generation pipeline
    │   ├── references/          ← Template cluster definitions
    │   └── assets/              ← Example outputs
    └── deep-research/
        ├── SKILL.md             ← Manifest
        ├── README.md            ← Install, usage, cost breakdown
        └── scripts/
            ├── research.py      ← CLI entry point
            └── sources/         ← One module per data source
```

Every skill is a directory under `skills/` containing at minimum a `SKILL.md` with frontmatter. See the [Agent Skills specification](https://agentskills.io/specification) for the format.

---

# The Agent Skills spec

A `SKILL.md` is just markdown with YAML frontmatter. Minimal example:

```markdown
---
name: my-skill
description: When the user wants to do X, this skill does Y. Trigger on phrases like "do X" or "help me Y".
---

# My Skill

Instructions for the agent go here.
```

**Required fields:**

| Field | Rules |
|---|---|
| `name` | 1–64 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen, no consecutive `--`, must match the folder name |
| `description` | 1–1024 chars. Should describe what the skill does **and** when to trigger it (the agent reads this to decide whether to activate). |

**Optional fields:** `license`, `compatibility` (1–500 chars), `metadata`, `allowed-tools` (space-delimited).

**Optional subfolders:** `scripts/`, `references/`, `assets/`.

# Validation

Every push runs the validator. You can run it locally before committing:

```bash
python3 scripts/validate-skills.py
```

Output:

```
✅ deep-research
✅ terminal-poster

🟢 All 2 skills valid against agentskills.io spec.
```

The validator enforces every rule above. If a skill fails, the exit code is non-zero — perfect for CI.

---

# Contributing

PRs welcome. Whether you're adding a new skill, improving an existing one, or fixing a bug, see [CONTRIBUTING.md](CONTRIBUTING.md) for the rules.

**TL;DR for adding a skill:**

1. Create `skills/<your-skill>/SKILL.md` with valid frontmatter
2. Add a `skills/<your-skill>/README.md` with install + usage docs
3. Run `python3 scripts/validate-skills.py` → must pass
4. Update the **Skills** table in this README
5. Open a PR

---

# Why this repo exists

Most agent skills live trapped inside one runtime — locked to Claude Code's `~/.claude/skills/` or Cursor's plugin format. The [agentskills.io](https://agentskills.io/specification) spec changes that: one folder, one manifest, works everywhere.

This repo is my contribution to that ecosystem. If you ship skills, the goal is the same — **portable, public, spec-compliant**. Open a PR.

---

# Credits

- 🎨 **`terminal-poster`** — visual pattern reverse-engineered from public posts by [@shannholmberg](https://x.com/shannholmberg) on X. The skill makes the look reproducible across topics; Shann designed the look itself.
- 🔍 **`deep-research`** — originally inspired by [`mvanhorn/last30days-skill`](https://github.com/mvanhorn/last30days-skill). The 30-day default window came from that upstream; the 8-source fan-out and monid routing were rebuilt from scratch.

---

# License

[MIT](LICENSE) © [@ravidsrk](https://github.com/ravidsrk)

If you build something with these skills, I'd love to see it — tag me on [X](https://x.com/ravidsrk) or open an issue.
