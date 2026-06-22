# agent-skills

Production-grade skills for AI agents — DNS migration, AWS migration, deep research, viral image generation.

# Project Structure

```
skills/        → 5 capability skills (each with SKILL.md + README.md + scripts/ references/ templates/)
docs/          → Per-runtime setup guides + skill-anatomy spec
scripts/       → Repo-level helpers (validate-skills.py)
assets/        → Banner image, screenshots
plugin.json    → Claude Code marketplace manifest
LICENSE        → MIT
```

# Skills

| Skill | Category | What it does |
|---|---|---|
| `cloudflare-dns` | 🌐 Infrastructure | DNS migration to Cloudflare + zone hardening |
| `namecheap-dns` | 🌐 Infrastructure | Namecheap XML API wrapper (handles wholesale-replace quirk) |
| `fly-to-aws-migration` | 🌐 Infrastructure | 7-phase Fly.io → AWS playbook with ≤9 min downtime |
| `deep-research` | 🔍 Research | 8-source parallel evidence orchestrator (X, Reddit, HN, GitHub, Polymarket, YouTube, Exa) |
| `terminal-poster` | 🎨 Creative | Retro-cyberpunk image posters (5 reusable templates, Nano Banana Pro) |

# Conventions

- Every skill lives in `skills/<name>/SKILL.md`
- YAML frontmatter requires `name` + `description` (1-1024 chars, includes both *what* and *when*)
- Each skill has its own `README.md` for human install + usage docs (separate from `SKILL.md` which is for agents)
- Scripts go in `skills/<name>/scripts/`, references in `references/`, templates in `templates/`
- Validate with `python3 scripts/validate-skills.py` before committing

# Commands

```bash
# Validate all skills
python3 scripts/validate-skills.py

# Browse a skill
cat skills/cloudflare-dns/SKILL.md

# Install one skill into Claude Code (link, don't copy)
ln -s "$(pwd)/skills/cloudflare-dns" ~/.claude/skills/cloudflare-dns
```

# Boundaries

- **Always:** Read `SKILL.md` before invoking a skill. Set required env vars in-memory only.
- **Never:** Hardcode secrets in scripts or commit them to git.
- **Never:** Add skills that are vague advice — every skill must be an actionable, verifiable workflow.
- **Never:** Duplicate skill content in the top-level README — link to `SKILL.md` and `README.md` instead.

# See Also

- [README.md](README.md) — Public-facing repo intro + install table
- [AGENTS.md](AGENTS.md) — Runtime-agnostic agent guidance + intent→skill mapping
- [docs/skill-anatomy.md](docs/skill-anatomy.md) — Skill structure specification
