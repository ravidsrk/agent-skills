# Skill Anatomy

The structural specification for skills in this repo. Aligns with the [Agent Skills spec](https://agentskills.io) used by Claude, Cursor, and most other agents.

# Directory Structure

Every skill lives in its own directory under `skills/`:

```
skills/
  skill-name/
    SKILL.md          # Required — the agent-facing manifest
    README.md         # Required — the human-facing install + usage docs
    scripts/          # Optional — runnable helpers (bash, python, etc.)
    references/       # Optional — long-form docs loaded on demand
    templates/        # Optional — boilerplate users copy into their projects
    assets/           # Optional — example outputs, fixtures
```

🟢 **`SKILL.md` and `README.md` are required.** Everything else is optional and should only exist if the skill actually uses it. Don't create empty folders to mirror other skills.

# `SKILL.md` Format

# Frontmatter (required)

```yaml
---
name: skill-name-with-hyphens
description: >-
  Does X. Use when [trigger phrase 1], [trigger phrase 2], [trigger phrase 3].
license: MIT
compatibility: Requires bash, curl, $SOMETHING_API_KEY env var.
metadata:
  version: "1.0.0"
  author: "@yourhandle"
allowed-tools: Bash Read Write Edit
---
```

**Required fields:**
- `name` — Lowercase, hyphen-separated, must match the directory name. 1-64 chars, no leading/trailing hyphens, no consecutive `--`.
- `description` — 1-1024 chars. **Must include both *what* the skill does AND *when* to use it.** The agent injects this into its system prompt — it's how the skill gets discovered.

**Recommended fields:**
- `license` — Defaults to repo LICENSE (MIT here)
- `compatibility` — One-line note on dependencies / env vars (1-500 chars)
- `metadata.version`, `metadata.author` — For tracking
- `allowed-tools` — Space-delimited list of tools the skill needs. Some runtimes use this to scope permissions.

# Body sections (no rigid template — use what makes sense)

This repo's skills are **capability skills** (discrete tools), not **lifecycle skills** (SDLC phases). The Addy Osmani-style "Overview / When to Use / Process / Rationalizations / Red Flags / Verification" template fits process skills well, but it adds noise for tool skills. Use it when it helps, skip it when it doesn't.

The patterns we use:

# For procedural skills (cloudflare-dns, fly-to-aws-migration)

```markdown
# Skill Title

[1-paragraph overview]

# When to use

[Bullet list of trigger phrases — when the agent should reach for this]

# When NOT to use

[Edge cases where another skill is better]

# Setup

[Env vars, tools required, permission scopes]

# The workflow

## Step 1 — [Verb] [Object]
[Concrete bash/python commands. Specifics, not vague advice.]

## Step 2 — ...

# Common gotchas

| Gotcha | Fix |
|---|---|
| Specific failure mode | How to recover |

# References

- `references/phases.md` — Detailed phase-by-phase
- `references/gotchas.md` — Long-form trap list
```

# For tool skills (deep-research, terminal-poster)

```markdown
# Skill Title

[1-paragraph overview + 1-paragraph value prop]

# Quick path

[The simplest possible invocation — single command]

# Configuration

[Spec format, options, examples]

# Modes / Templates / Variations

[Specific patterns the agent picks between]
```

# `README.md` (the human-facing file)

`SKILL.md` is for the agent. `README.md` is for the human installing the skill. Don't conflate them.

A good skill README covers:

1. **What it does** — single sentence
2. **When to use** — trigger phrases
3. **Install** — clone / link / env vars
4. **Usage** — runnable examples for the top 3-5 commands
5. **Gotchas** — the failures that bite first-time users
6. **File layout** — tree of what's in the folder
7. **Pairs with** — links to related skills
8. **License**

# Naming

- Skill directories: `lowercase-hyphen-separated`
- Skill manifest: `SKILL.md` (always uppercase, exactly this name)
- Readmes: `README.md`
- Supporting files: `lowercase-hyphen-separated.md`
- References go inside the skill folder (`skills/<name>/references/`), not at repo root, unless they're shared across multiple skills (we don't have any shared references yet)

# Cross-skill references

Reference other skills by name and relative path:

```markdown
See [`cloudflare-dns`](../cloudflare-dns/) for the DNS cutover step.
```

🔴 **Don't duplicate content across skills.** If two skills need the same recipe, factor it out and have both link to it.

# Writing principles

1. **Process over knowledge.** Skills are workflows, not reference docs. Steps, not facts.
2. **Specific over general.** `Run \`terraform apply\`` beats `Apply the Terraform`.
3. **Evidence over assumption.** Every "verify this worked" step needs proof (a command that returns 0, a curl that returns 200, etc.).
4. **Progressive disclosure.** Main `SKILL.md` is the entry point. Long-form docs live in `references/` and load only when needed.
5. **Token-conscious.** Every paragraph must earn its place. If removing it wouldn't change the agent's behavior, remove it.

# Validation

Before committing:

```bash
python3 scripts/validate-skills.py
```

Hard failures (non-zero exit):

- Missing / malformed frontmatter (must open + close with `---`)
- `name` missing, out of the 1–64 char range, containing invalid characters, or not matching the folder name
- `description` missing or outside the 1–1024 char range
- `compatibility` (if present) outside 1–500 chars
- `README.md` missing next to `SKILL.md`
- Any inline-code (`` `scripts/foo.py` ``) or markdown-link (`](references/bar.md)`) reference to a path under `scripts/`, `references/`, `templates/`, or `assets/` that doesn't resolve on disk

Warnings (not fatal, but flagged):

- `description` missing "use when" / "when the user" / "when you" / "trigger" phrasing

CI (`.github/workflows/validate.yml`) runs the same script on every push and PR against `main`.

# Anti-patterns

🔴 **Vague advice** — "Make sure tests pass." Use: "Run `npm test` and confirm exit code 0."

🔴 **Knowledge-dump skills** — A skill that's just "everything about Postgres" isn't a skill, it's a wiki page. Skills are *processes*.

🔴 **Hidden state** — A skill that requires the agent to remember context from a previous session. Skills should be re-entrant: an agent should be able to pick up at any step.

🔴 **Empty `scripts/` folders** — If your skill doesn't have scripts, don't create the folder. Don't pad the skill to look more substantial than it is.

🔴 **`SKILL.md` content duplicated in `README.md`** — They serve different audiences. The `README.md` is install + examples for humans. The `SKILL.md` is the workflow the agent follows. Some overlap is fine; identical content is wasted tokens.

🔴 **Hardcoded secrets** — Read all auth from env vars at runtime. Never write tokens to disk, configs, or URLs.
