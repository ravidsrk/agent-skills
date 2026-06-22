# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, GitHub Copilot, Antigravity, Gemini CLI, OpenCode, Mogra, etc.) when working with code in this repository.

# Repository Overview

A collection of production-grade skills for AI agents, focused on real infrastructure and content work — DNS migration, AWS migration, multi-source research, viral image generation. Each skill is battle-tested in production, not theoretical.

Unlike SDLC-shaped skill packs (e.g. `addyosmani/agent-skills`), these are **capability skills** — discrete tools an agent reaches for when the task requires them, not lifecycle steps that fire in sequence.

# Skill Discovery

When working in this repo:

1. **Use the skill that matches the task.** Check `skills/` for relevant capabilities before implementing from scratch.
2. **Skills auto-activate via description.** Every `SKILL.md` description includes "Use when..." trigger phrases. Match those.
3. **Read `SKILL.md` top-to-bottom** before invoking — every skill has setup requirements (env vars, dependencies) declared in frontmatter.

# Intent → Skill Mapping

| User says... | Use skill |
|---|---|
| "Move my DNS to Cloudflare" / "manage Cloudflare records" / "harden a zone" | [`cloudflare-dns`](skills/cloudflare-dns/SKILL.md) |
| "Add a CNAME / MX / A record on Namecheap" / "link my domain to my Fly/Vercel app" | [`namecheap-dns`](skills/namecheap-dns/SKILL.md) |
| "Migrate from Fly to AWS" / "leave Fly" / "ECS migration" / "AWS migration" | [`fly-to-aws-migration`](skills/fly-to-aws-migration/SKILL.md) |
| "Research X" / "deep dive on Y" / "what's the discourse on Z" | [`deep-research`](skills/deep-research/SKILL.md) |
| "Generate a viral poster" / "terminal aesthetic infographic" / "agent stack visualization" | [`terminal-poster`](skills/terminal-poster/SKILL.md) |

# Execution Model

For every request:

1. **Determine if any skill applies** — even a 30% match is worth checking
2. **Read the matching `SKILL.md`** in full before acting
3. **Follow the skill's process exactly** — don't partially apply or skip steps
4. **Verify required env vars** are set before running scripts (each skill's README lists them)
5. **If multiple skills could apply**, prefer the more specific one (e.g. `cloudflare-dns` over a generic "use the API" approach)

# Repository Conventions

- Every skill lives in `skills/<name>/` with at minimum `SKILL.md` + `README.md`
- YAML frontmatter has `name` (must match directory) + `description` (1-1024 chars, includes both *what* and *when*)
- Scripts go in `skills/<name>/scripts/`
- References (loaded on demand) go in `skills/<name>/references/`
- Templates (boilerplate users copy into their projects) go in `skills/<name>/templates/`
- Top-level `docs/` is for repo-level setup guides, not skill-specific content

# Boundaries

- **Always:** Read `SKILL.md` before invoking. Set required env vars at runtime (in-memory only, never write to disk).
- **Always:** Validate skills with `python3 scripts/validate-skills.py` before committing changes.
- **Never:** Hardcode secrets in skill scripts. Use env vars.
- **Never:** Add a skill that's vague advice instead of an actionable, verifiable workflow.
- **Never:** Duplicate skill instructions in the README — link to `SKILL.md` instead.

# Common Operations

- **Add a new skill:** Copy structure from an existing one (e.g. `cloudflare-dns`), update `SKILL.md` frontmatter, add `README.md`, run validator.
- **Validate all skills:** `python3 scripts/validate-skills.py`
- **Test locally before committing:** Read your `SKILL.md` as if you were a fresh agent — would you know what to do?

# See Also

- [docs/skill-anatomy.md](docs/skill-anatomy.md) — Skill structure specification
- [docs/getting-started.md](docs/getting-started.md) — Setup for any runtime
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution guidelines
