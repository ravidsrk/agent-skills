# Mogra Setup

[Mogra](https://mogra.dev) auto-discovers skills from `/workspace/.mogra/skills/`. Two install paths.

# 🟢 Path 1: Symlink (recommended — repo lives elsewhere, skills resolve to it)

```bash
cd /workspace
git clone https://github.com/ravidsrk/agent-skills.git

mkdir -p /workspace/.mogra/skills
for s in agent-skills/skills/*/; do
  name=$(basename "$s")
  ln -sf "$(pwd)/$s" "/workspace/.mogra/skills/$name"
done

# Verify Mogra sees them
ls /workspace/.mogra/skills/
```

Restart your Mogra session — skills appear in the active skill list.

# 🟢 Path 2: Direct clone into `.mogra/skills/`

```bash
cd /workspace/.mogra/skills
git clone https://github.com/ravidsrk/agent-skills.git
# Mogra will pick up the nested skills/ folder — but cleaner to:
mv agent-skills/skills/* .
rm -rf agent-skills
```

# Env vars

Mogra auto-injects env vars from `/workspace/.mogra/.env` and `~/.env`. Add the ones your skills need:

```bash
# Append to /workspace/.mogra/.env (DON'T commit this file)
CLOUDFLARE_API_KEY=cfat_...        # cloudflare-dns: account token
NAMECHEAP_API_KEY=...
NAMECHEAP_API_USER=your-account
OPENROUTER_API_KEY=...              # terminal-poster
MONID_API_KEY=...                   # deep-research
AWS_PROFILE=migration               # fly-to-aws-migration
FLY_API_TOKEN=...                   # fly-to-aws-migration
CLOUDFLARE_API_TOKEN=...            # fly-to-aws-migration: scoped Zone:DNS:Edit token
CLOUDFLARE_ZONE_ID=...              # fly-to-aws-migration
# clean-sweep needs no env vars — it requires the Orca runtime + gh CLI on PATH
```

🔴 **`.env` files are read-only to skills.** The Mogra agent never modifies them. If a skill needs a new env var, add it manually.

# Verify activation

In a Mogra chat, send:

> *"Generate a terminal-style poster for our deployment pipeline"*

Mogra should announce it's using `terminal-poster`.

If not, check that the skill is listed:

```bash
ls /workspace/.mogra/skills/
cat /workspace/.mogra/skills/terminal-poster/SKILL.md | head -5
```

# Updating

```bash
cd /workspace/agent-skills    # or wherever you cloned
git pull
```

Symlinks resolve instantly. If you used Path 2, re-clone and replace.
