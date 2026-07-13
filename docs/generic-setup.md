# Setup for Codex, GitHub Copilot, and any other agent

Skills are plain Markdown. They work with any agent that accepts system prompts, rules files, or instruction documents.

# The universal pattern

Every skill is a single `SKILL.md` file with YAML frontmatter on top. To load it into any agent:

1. **Read the skill content** — `cat skills/<name>/SKILL.md`
2. **Paste into your agent's system prompt / instructions / rules file**
3. **Set the env vars** the skill requires (listed in the skill's `README.md`)
4. **Trigger** with a phrase matching the skill's "Use when..." description

# GitHub Copilot

Copilot reads `.github/copilot-instructions.md`. To load skills:

```bash
mkdir -p .github
# Concatenate the skills you want active in this project
cat skills/cloudflare-dns/SKILL.md \
    skills/namecheap-dns/SKILL.md \
    > .github/copilot-instructions.md
```

🟡 Copilot doesn't run scripts — it'll suggest commands inline. That's fine for skills like `cloudflare-dns` where the agent's job is to tell you which `scripts/migrate.sh` invocation to run.

# Codex CLI

```bash
# Codex reads AGENTS.md from the working directory — put the skill content there
# (there is no --system-file flag)
cat skills/deep-research/SKILL.md >> AGENTS.md
codex "research the state of AI agent harnesses"
```

# Any OpenAI-API-compatible agent

```python
import openai

with open("skills/cloudflare-dns/SKILL.md") as f:
    skill = f.read()

response = openai.chat.completions.create(
    model="gpt-4o",
    messages=[
        {"role": "system", "content": skill},
        {"role": "user", "content": "Move example.com to Cloudflare"}
    ]
)
```

# Anthropic Claude API

```python
import anthropic

with open("skills/cloudflare-dns/SKILL.md") as f:
    skill = f.read()

client = anthropic.Anthropic()
response = client.messages.create(
    model="claude-sonnet-4",
    system=skill,
    messages=[{"role": "user", "content": "Move example.com to Cloudflare"}],
    max_tokens=4096
)
```

# Multi-skill loading

To make multiple skills available simultaneously, concatenate them with a separator and a top-level dispatcher:

```bash
{
  cat <<'EOF'
You have multiple skills available. Pick the matching one based on the user's request:

- cloudflare-dns: Cloudflare DNS migration + management
- namecheap-dns: Namecheap DNS records via XML API
- fly-to-aws-migration: Fly.io to AWS migration playbook

---
EOF
  for s in cloudflare-dns namecheap-dns fly-to-aws-migration; do
    echo ""
    echo "# === Skill: $s ==="
    echo ""
    cat skills/$s/SKILL.md
  done
} > /tmp/combined-skills.md
```

Then pass `/tmp/combined-skills.md` as the system prompt.

🟡 **Token cost grows linearly with skill count.** For agents like ChatGPT with no skill-discovery layer, only load the skills you actually need.

# Env vars

Every skill reads its secrets from environment variables at runtime. Set them in your shell:

```bash
export CLOUDFLARE_API_KEY=cfat_...
export NAMECHEAP_API_KEY=...
# etc.
```

🔴 **Never paste secrets into the agent's system prompt.** Skills read from `$ENV_VAR` references at the shell level, not from the prompt context.

# Verification

If the agent acknowledges the skill (e.g. "I'll follow the cloudflare-dns workflow"), it's loaded. If it ignores the skill and improvises, the system prompt isn't being applied — check your runtime's prompt-loading mechanism.
