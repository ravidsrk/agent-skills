# Cursor Setup

Cursor doesn't have native skill discovery, but it accepts skill content via `.cursor/rules/` files or pasted system prompts.

# 🟢 Path 1: Per-project rules (recommended)

In any Cursor project where you want a skill loaded:

```bash
mkdir -p .cursor/rules
cp /path/to/agent-skills/skills/cloudflare-dns/SKILL.md .cursor/rules/cloudflare-dns.md
```

Cursor automatically reads `.cursor/rules/*.md` and includes them in every chat's context.

# 🟢 Path 2: Symlink the whole skills directory

```bash
cd /path/to/agent-skills
mkdir -p ~/.cursor/skills  # or ./project/.cursor/rules
for s in skills/*/; do
  name=$(basename "$s")
  ln -sf "$(pwd)/$s/SKILL.md" "$HOME/.cursor/skills/$name.md"
done
```

# 🟡 Path 3: Manual paste

For one-off use, copy the contents of `SKILL.md` and paste into Cursor's chat as a system message before your actual request.

# Env vars

Cursor inherits env vars from your shell. Set them in `~/.zshrc` / `~/.bashrc`:

```bash
export CLOUDFLARE_API_KEY=cfat_...
export OPENROUTER_API_KEY=...
# etc.
```

🔴 **Don't put secrets in `.cursor/rules/`** — those files get sent to the model on every request. Secrets stay in env vars.

# Verify activation

In Cursor chat, send a request that matches the skill's trigger phrases:

> *"Add a CNAME for docs.example.com pointing at my Fly app"*

If the skill is loaded, Cursor's response will reference the workflow defined in `namecheap-dns/SKILL.md`.

# Updating

```bash
cd /path/to/agent-skills && git pull
# Copies need to be redone; symlinks update automatically
```

# Notes

🟡 **Cursor's rules-file context is per-project.** If you want skills available globally, use the symlink approach with `~/.cursor/`.

🟡 **No script execution.** Cursor reads `SKILL.md` as context but doesn't run `scripts/` directly. Skills with bash helpers (like `cloudflare-dns/scripts/migrate.sh`) work fine — Cursor will tell you which command to run, you run it.
