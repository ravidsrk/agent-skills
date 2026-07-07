# OpenCode Setup

OpenCode uses a **skill-driven execution model** via the `skill` tool and `AGENTS.md` discovery.

# Install

OpenCode auto-discovers skills from `./skills/` relative to your project root, or globally from `~/.opencode/skills/`.

# 🟢 Path 1: Symlink into `~/.opencode/skills/`

```bash
git clone https://github.com/ravidsrk/agent-skills.git
mkdir -p ~/.opencode/skills
for s in agent-skills/skills/*/; do
  name=$(basename "$s")
  ln -sf "$(pwd)/$s" "$HOME/.opencode/skills/$name"
done
```

# 🟢 Path 2: Project-local

Inside any OpenCode project:

```bash
git clone https://github.com/ravidsrk/agent-skills.git .opencode/agent-skills
ln -s .opencode/agent-skills/skills .opencode/skills
```

# Repo-level `AGENTS.md`

This repo ships an [`AGENTS.md`](../AGENTS.md) at the root. OpenCode reads it automatically when you open the agent-skills folder — it tells OpenCode:

1. Which skills exist
2. Which user intents map to which skill
3. The mandatory rule: *"if a task matches a skill, you MUST invoke it"*

If you only want the skills (not the AGENTS.md rules), copy the `skills/` directory and ignore the root AGENTS.md.

# Env vars

OpenCode inherits from the shell. Set in `~/.zshrc` / `~/.bashrc`:

```bash
export CLOUDFLARE_API_KEY=cfat_...       # cloudflare-dns: account token
export NAMECHEAP_API_KEY=...
export NAMECHEAP_API_USER=your-account
export MONID_API_KEY=...                 # deep-research
export OPENROUTER_API_KEY=...            # terminal-poster
export AWS_PROFILE=migration             # fly-to-aws-migration
export FLY_API_TOKEN=...                 # fly-to-aws-migration
export CLOUDFLARE_API_TOKEN=...          # fly-to-aws-migration: scoped Zone:DNS:Edit token
export CLOUDFLARE_ZONE_ID=...            # fly-to-aws-migration
# clean-sweep: no env vars — requires Orca runtime + `gh` CLI on PATH
```

# Verify activation

In OpenCode, send a request matching a skill's triggers:

> *"Migrate my Fly project to AWS"*

OpenCode should invoke the `skill` tool with `fly-to-aws-migration` and follow the workflow.

# How OpenCode reads skills

OpenCode's flow:

1. **Read `AGENTS.md`** at project root → understands the skill mapping rules
2. **Read `skills/<name>/SKILL.md`** when a skill is invoked → loads the workflow
3. **Execute scripts** in `skills/<name>/scripts/` as needed
4. **Load `references/`** progressively when the workflow points to them

🟢 **Progressive disclosure works out of the box** — OpenCode won't load `references/gotchas.md` until the skill workflow actually references it.

# Updating

```bash
cd /path/to/agent-skills && git pull
```

Symlinks update automatically.

# See also

- [OpenCode docs on AGENTS.md](https://opencode.ai/docs/agents) (official)
- This repo's [`AGENTS.md`](../AGENTS.md) — the actual file OpenCode reads
