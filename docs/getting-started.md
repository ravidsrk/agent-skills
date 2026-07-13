# Getting Started

## The skills

Five capability skills — cloudflare-dns, namecheap-dns, fly-to-aws-migration, deep-research (monid), terminal-poster. Work on any harness; set the env vars listed in each README.

The autonomous Orca fleets that used to live here moved to [ravidsrk/orca-fleet](https://github.com/ravidsrk/orca-fleet).

**deep-research name collision:** this repo's skill is monid-based. Other packs may use the same name for a different workflow — last symlink wins under `~/.claude/skills/`.



This guide gets you from "I cloned the repo" to "the agent is using a skill" in 5 minutes, regardless of which AI runtime you use.

# What's a skill?

A **skill** is a packaged workflow + the scripts and references needed to follow it. It lives in a folder:

```
skills/cloudflare-dns/
├── SKILL.md      ← Manifest (frontmatter + instructions the agent reads)
├── README.md     ← Human docs (install, usage, examples)
└── scripts/      ← Runnable helpers the workflow uses
```

Agents discover skills by reading the YAML frontmatter at the top of each `SKILL.md`. The `description` field tells the agent both *what* the skill does and *when* to use it. If the user's task matches the description's trigger phrases, the skill activates.

# 5-minute install (any runtime)

# 1. Clone

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills
```

# 2. Pick a skill

```bash
ls skills/
# cloudflare-dns  namecheap-dns  fly-to-aws-migration  deep-research  terminal-poster
```

Read its `README.md` for what it does and what env vars it needs.

# 3. Load it into your runtime

The pattern depends on the runtime. Pick the one matching your setup:

- 🟢 **[Claude Code](claude-code-setup.md)** (recommended — symlink install)
- 🟢 **[Mogra](mogra-setup.md)** (works out of the box if you use Mogra)
- 🟡 **[Cursor](cursor-setup.md)** (paste `SKILL.md` into `.cursor/rules/`)
- 🟡 **[OpenCode](opencode-setup.md)** (use `AGENTS.md` + the `skill` tool)
- 🟡 **[Codex / Other Agents](generic-setup.md)** (skills are plain Markdown — paste into system prompt)

# 4. Set the env vars

Each skill's `README.md` lists what it needs. Quick reference for all 5:

```bash
# cloudflare-dns
export CLOUDFLARE_API_KEY=cfat_...
export CLOUDFLARE_GLOBAL_API_KEY=...    # only for new-zone creation
export CLOUDFLARE_EMAIL=you@example.com

# namecheap-dns
export NAMECHEAP_API_KEY=...
export NAMECHEAP_API_USER=your-account

# fly-to-aws-migration
export AWS_PROFILE=migration
export FLY_API_TOKEN=...
# (also uses CLOUDFLARE_API_KEY for the DNS cutover phase)

# deep-research
export MONID_API_KEY=...

# terminal-poster
export OPENROUTER_API_KEY=...
```

🔴 **Never commit `.env` files.** All skills read env vars at runtime — they're never written to disk.

# 5. Verify activation

In your agent, ask something the skill should respond to:

| Skill | Trigger phrase |
|---|---|
| `cloudflare-dns` | *"Move example.com's DNS to Cloudflare"* |
| `namecheap-dns` | *"Add a CNAME for docs.example.com pointing at my Fly app"* |
| `fly-to-aws-migration` | *"Migrate my Fly project to AWS"* |
| `deep-research` | *"Do a deep dive on AI agent harness engineering"* |
| `terminal-poster` | *"Generate a terminal-style poster for our agent stack"* |

The agent should announce that it's loading the matching skill before proceeding.

# Validating skills (for contributors)

If you're modifying or adding skills:

```bash
python3 scripts/validate-skills.py
```

The validator checks:
- Frontmatter has required `name` + `description` fields
- `name` is valid (lowercase, hyphenated, matches directory)
- `description` is 1-1024 chars
- Skill folder structure is sane

# Next steps

- Browse [individual skill READMEs](../skills/) for deep dives
- Read [skill-anatomy.md](skill-anatomy.md) to understand the format
- See [CONTRIBUTING.md](../CONTRIBUTING.md) to add your own skills
