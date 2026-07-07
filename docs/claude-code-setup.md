# Claude Code Setup

Three install paths — pick whichever fits.

# 🟢 Path 1: Symlink (recommended for active development)

```bash
git clone https://github.com/ravidsrk/agent-skills.git
cd agent-skills

# Link every skill
mkdir -p ~/.claude/skills
for s in skills/*/; do
  name=$(basename "$s")
  ln -sf "$(pwd)/$s" "$HOME/.claude/skills/$name"
done

# Verify
ls ~/.claude/skills/
# clean-sweep  cloudflare-dns  deep-research  fly-to-aws-migration  namecheap-dns  terminal-poster
```

🟢 **Why this approach:** edits to your clone instantly reflect in Claude Code. Skills update via `git pull`. No reinstall step.

# 🟡 Path 2: Copy (snapshot install)

```bash
git clone https://github.com/ravidsrk/agent-skills.git /tmp/agent-skills
cp -r /tmp/agent-skills/skills/* ~/.claude/skills/
```

🟡 **Tradeoff:** updates require re-running the copy. Good for production environments where you don't want a moving target.

# 🟢 Path 3: Plugin manifest (when you want full repo discovery)

The repo ships a `.claude-plugin/plugin.json` manifest, so Claude Code can treat the whole repo as a plugin bundle.

```bash
git clone https://github.com/ravidsrk/agent-skills.git ~/.claude/plugins/agent-skills
```

Claude Code picks up `skills/`, scripts, and any `agents/` (when we add them) automatically.

# Per-skill env vars

Each skill needs different secrets. Set them in your shell or in Claude Code's env-vars panel:

| Skill | Required env vars |
|---|---|
| `cloudflare-dns` | `CLOUDFLARE_API_KEY` (account token), `CLOUDFLARE_GLOBAL_API_KEY` + `CLOUDFLARE_EMAIL` (only for new-zone creation) |
| `namecheap-dns` | `NAMECHEAP_API_KEY`, `NAMECHEAP_API_USER` |
| `fly-to-aws-migration` | `AWS_PROFILE`, `FLY_API_TOKEN`, `CLOUDFLARE_API_TOKEN` (scoped Zone:DNS:Edit — legacy `CLOUDFLARE_EMAIL` + `CLOUDFLARE_GLOBAL_API_KEY` still accepted), `CLOUDFLARE_ZONE_ID` |
| `deep-research` | `MONID_API_KEY` |
| `terminal-poster` | `OPENROUTER_API_KEY` |
| `clean-sweep` | none — requires Orca runtime + `gh` CLI on PATH |

```bash
# Example: add to ~/.zshrc or ~/.bashrc
export CLOUDFLARE_API_KEY=cfat_...
export MONID_API_KEY=...
export OPENROUTER_API_KEY=...
```

🔴 **Don't commit `.env` files.** All skills read env vars at runtime. They're never written to disk by the skill code.

# Verify a skill is active

In Claude Code, send:

> *"Move example.com's DNS to Cloudflare"*

You should see Claude announce that it's using the `cloudflare-dns` skill before responding.

If Claude doesn't announce a skill, check:

1. `ls ~/.claude/skills/` shows the skill directory
2. The skill's `SKILL.md` has valid YAML frontmatter (run `python3 scripts/validate-skills.py` from the cloned repo)
3. Claude Code's settings have skills enabled (Settings → Skills → Enabled)

# Updating

```bash
cd ~/path/to/agent-skills
git pull
```

If you used Path 1 (symlinks), updates are instant. Path 2 requires re-copying.

# Uninstalling

```bash
# Remove individual skill
rm ~/.claude/skills/cloudflare-dns

# Remove all
rm -rf ~/.claude/skills/*
```
