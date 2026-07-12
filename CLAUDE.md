# agent-skills

Production-grade skills for AI agents — DNS migration, AWS migration, deep research, viral image generation.

# Project Structure

```
skills/        → 46 skills: 5 capability + 30 Orca orchestration/fleet + 2 autonomous peers
                 + 9 fleet-ops (standing/doctor/blackbox/steward/train/quorum/decompose/ephemeral/memory)
                 (each with SKILL.md + README.md + scripts/ references/ templates/ assets/)
docs/          → Per-runtime setup guides + skill-anatomy spec + review/remediation logs
scripts/       → Repo-level helpers (validate-skills.py, sync-orca-coord.py, test-orca-coord.sh)
scripts/orca-coord/ → CANONICAL shared fleet helpers; skill copies are GENERATED (see MANIFEST)
tests/         → Behavioral tests for the orca-coord substrate
assets/        → Banner image, screenshots
.claude-plugin/plugin.json → Claude Code marketplace manifest
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

The 30 Orca orchestration/fleet skills and the 2 autonomous peers (`clean-sweep`,
`spec-to-ship`) are cataloged in [README.md](README.md) and mapped in
[AGENTS.md](AGENTS.md) (intent map, review routing, runtime dependency matrix).
Editing a fleet skill? The `scripts/` helpers inside each skill are GENERATED from
`scripts/orca-coord/` — edit the canonical file and run `python3 scripts/sync-orca-coord.py`.

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
