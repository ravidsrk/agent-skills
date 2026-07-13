# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Cursor, GitHub Copilot, Antigravity, Gemini CLI, OpenCode, Mogra, etc.) when working with code in this repository.

# Repository Overview

A collection of production-grade **capability skills** for AI agents, focused on real infrastructure and content work — DNS migration, AWS migration, multi-source research, viral image generation. Each skill is battle-tested in production, not theoretical.

Unlike SDLC-shaped skill packs (e.g. `addyosmani/agent-skills`), these are discrete tools an agent reaches for when the task requires them, not lifecycle steps that fire in sequence.

The autonomous Orca fleets that used to live here moved to [ravidsrk/orca-fleet](https://github.com/ravidsrk/orca-fleet). This repo is capability skills only.

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

# Imagery & Banners

Every skill ships with a **per-skill banner** at `skills/<name>/assets/banner.{jpg,png}`, plus a matching `banner-prompt.txt` reproducer next to it. The main `assets/banner.jpg` is the repo hero (clean typography on warm cream paper).

**Design language (keep new skills consistent):**

- **Style:** Clean minimalist isometric illustration, Stripe documentation aesthetic. NOT photorealistic, NOT cyberpunk, NOT dense text.
- **Aspect ratio:** 2:1 (~1200×600) for skill banners; 16:9 for the repo hero.
- **Background:** Soft warm cream `#F8F4EE` (optionally with a faint horizontal gradient).
- **Ink:** Dark slate `#1F2937`. **Card faces:** White `#FFFFFF` with subtle drop shadows.
- **Accent:** ONE skill-specific brand color (e.g. Cloudflare orange, Fly purple, etc.).
- **Composition:** Tell the skill's story at a glance — a left→right journey, a radial fan-out, a central object with outputs around it.
- **Required labels:** Top-left `skills/<name>` in small monospace; bottom-center thin line + one-sentence caption.

**Generation:**

```bash
# Requires $OPENROUTER_API_KEY
bash skills/terminal-poster/scripts/generate.sh \
  skills/<name>/assets/banner-prompt.txt \
  skills/<name>/assets/banner.jpg
```

- **Model:** Nano Banana Pro (`google/gemini-3-pro-image-preview`) via OpenRouter
- **Cost:** ~$0.002 per image
- **Latency:** ~30 seconds — generate candidates in parallel via background bash when iterating

**Known gotchas (DO NOT REPEAT):**

🔴 **Nano Banana Pro often returns JPEG even when you write to `.png`.** Sniff magic bytes after generation (`\xff\xd8\xff` = JPEG, `\x89PNG` = PNG) and rename. The generator script warns but doesn't auto-rename.

🔴 **The model drops, duplicates, or garbles text labels.** Add explicit constraints ("the word X must appear exactly once", "do not duplicate any label", "do not render fake domain names"), render labels OUTSIDE cards, and use abstract dot patterns where you'd otherwise show placeholder text.

🔴 **Always vision-audit before shipping.** After generation, run `read(path, prompt="check spelling and label correctness")` — it catches problems invisible at thumbnail size. If text is wrong, regenerate with a tighter prompt; don't upscale-fix.

**Adding a banner to a new skill:**

1. Write `skills/<name>/assets/banner-prompt.txt` following the design language above
2. Generate with the command above
3. Sniff format and rename if needed
4. Vision-audit for spelling/legibility
5. Reference in the skill's README above the H1 description
6. Commit both the image AND the prompt — reproducers are first-class artifacts in this repo

# See Also

- [docs/skill-anatomy.md](docs/skill-anatomy.md) — Skill structure specification
- [docs/getting-started.md](docs/getting-started.md) — Setup for any runtime
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution guidelines
