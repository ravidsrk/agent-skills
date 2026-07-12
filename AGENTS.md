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
| "the docs are ready — build the whole product" / "spec to ship" / autonomous greenfield build | [`spec-to-ship`](skills/spec-to-ship/SKILL.md) |
| "clean sweep the issues" / "fix everything in this audit" / autonomous fix-everything pass | [`clean-sweep`](skills/clean-sweep/SKILL.md) |

| "matt ship" / grill then fleet implement / idea to tickets to AFK agents | [`matt-ship`](skills/matt-ship/SKILL.md) |
| "wayfinder fleet" / foggy multi-session map with parallel research | [`wayfinder-fleet`](skills/wayfinder-fleet/SKILL.md) |
| "design it thrice" / radical interface options in isolation | [`design-it-thrice`](skills/design-it-thrice/SKILL.md) |
| "review matrix" / dual-axis PR review under Orca | [`review-matrix`](skills/review-matrix/SKILL.md) |
| "triage factory" / drain ready-for-agent | [`triage-to-fleet`](skills/triage-to-fleet/SKILL.md) / [`ready-agent-drain`](skills/ready-agent-drain/SKILL.md) |
| "diagnose swarm" / hard intermittent bug multi-agent | [`diagnose-swarm`](skills/diagnose-swarm/SKILL.md) |
| "architecture sprint" / deepen modules with a fleet | [`architecture-sprint`](skills/architecture-sprint/SKILL.md) |
| "research then grill" | [`research-then-grill`](skills/research-then-grill/SKILL.md) |
| "adversarial ticket" / red-team acceptance criteria | [`adversarial-ticket`](skills/adversarial-ticket/SKILL.md) |
| "model jury" / multi-model implement compare | [`model-jury`](skills/model-jury/SKILL.md) |
| course/content wayfinder full journey | [`content-wayfinder`](skills/content-wayfinder/SKILL.md) |
| "ship fleet" / open PR autonomously after build | [`gstack-ship-fleet`](skills/gstack-ship-fleet/SKILL.md) |
| "qa fleet" / autonomous browser QA | [`qa-fleet`](skills/qa-fleet/SKILL.md) |
| "cso fleet" / OWASP autonomous audit | [`cso-fleet`](skills/cso-fleet/SKILL.md) |
| "autoplan fleet" / autonomous plan gauntlet | [`autoplan-fleet`](skills/autoplan-fleet/SKILL.md) |
| "full sprint fleet" / plan-build-verify-ship | [`full-sprint-fleet`](skills/full-sprint-fleet/SKILL.md) |
| "headless mode" / guard policy for fleets | [`headless-mode`](skills/headless-mode/SKILL.md) / [`guard-policy`](skills/guard-policy/SKILL.md) |
| "benchmark fleet" / perf vs baseline on staging URLs | [`benchmark-fleet`](skills/benchmark-fleet/SKILL.md) |
| "canary fleet" / post-deploy monitoring, human rollback gate | [`canary-fleet`](skills/canary-fleet/SKILL.md) |
| "design shotgun fleet" / parallel design variants, human pick | [`design-shotgun-fleet`](skills/design-shotgun-fleet/SKILL.md) |
| "docs fleet" / Diataxis docs after code lands | [`docs-fleet`](skills/docs-fleet/SKILL.md) |
| "health fleet" / typecheck-lint-tests-deps dashboard | [`health-fleet`](skills/health-fleet/SKILL.md) |
| "investigate fleet" / evidence → root cause → fix swarm | [`investigate-fleet`](skills/investigate-fleet/SKILL.md) |
| "ios qa fleet" / device QA over USB or Tailscale | [`ios-qa-fleet`](skills/ios-qa-fleet/SKILL.md) |
| "office hours async" / research pack + forcing questions for the human | [`office-hours-async`](skills/office-hours-async/SKILL.md) |
| "retro cron" / scheduled weekly retrospective batch | [`retro-cron`](skills/retro-cron/SKILL.md) |
| "review prod fleet" / passes-CI-breaks-in-prod hunt | [`review-prod-fleet`](skills/review-prod-fleet/SKILL.md) |
| "spec issue fleet" / gstack /spec into issue, then implement fleet | [`spec-issue-fleet`](skills/spec-issue-fleet/SKILL.md) |
| "schedule the fleet" / nightly drain / standing run / cron fleet | [`standing-fleet`](skills/standing-fleet/SKILL.md) |
| "the fleet stalled" / revive workers / self-healing run | [`fleet-doctor`](skills/fleet-doctor/SKILL.md) |
| "coordinator died" / resume the run / run status / audit a run | [`run-blackbox`](skills/run-blackbox/SKILL.md) |
| "too many gates" / auto-decide mechanical / gate policy | [`gate-steward`](skills/gate-steward/SKILL.md) |
| "merge queue" / PRs racing / serialize merges to BASE | [`merge-train`](skills/merge-train/SKILL.md) |
| "drain the backlog" / close every issue / backlog zero | [`backlog-zero`](skills/backlog-zero/SKILL.md) |
| "harden this" / security sweep / red team / close the security loop | [`red-team-harden`](skills/red-team-harden/SKILL.md) |
| "kill the flaky tests" / deflake / flake zero | [`flake-zero`](skills/flake-zero/SKILL.md) |
| "build and ship this feature" / feature factory / spec to shipped feature | [`feature-factory`](skills/feature-factory/SKILL.md) |
| "vote on it" / second opinions / consensus / adversarial verify | [`quorum`](skills/quorum/SKILL.md) |
| "decompose this spec" / build the task DAG / "No tasks found" | [`spec-decompose`](skills/spec-decompose/SKILL.md) |
| "run it in sandboxes" / disposable workers / untrusted work | [`ephemeral-fleet`](skills/ephemeral-fleet/SKILL.md) |
| "stop re-hitting the same gotchas" / fleet learnings / gate cold reviewers | [`fleet-memory`](skills/fleet-memory/SKILL.md) |


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

🔴 **The model drops, duplicates, or garbles text labels.** Past failures:
- "HACKER NUDS" instead of "HACKER NEWS"
- GITHUB rendered twice while EXA was dropped entirely
- Fake domain "example.com" rendered as "onomplo.com" / "ouomplo.com"

Fixes:
- Add explicit constraints in the prompt: "the word X must appear exactly once", "do not duplicate any label", "do not render fake domain names"
- Render labels OUTSIDE cards (below them), not inside
- Use abstract dot patterns where you'd otherwise show placeholder text

🔴 **Always vision-audit before shipping.** After generation, run `read(path, prompt="check spelling and label correctness")` — it catches problems that are invisible at thumbnail size. If text is wrong, regenerate with a tighter prompt; don't try to upscale-fix.

**Adding a banner to a new skill:**

1. Write `skills/<name>/assets/banner-prompt.txt` following the design language above
2. Generate with the command above
3. Sniff format and rename if needed
4. Vision-audit for spelling/legibility
5. Reference in the skill's README: `<img src="assets/banner.{jpg,png}" alt="<name> — <one-line description>" width="100%">` above the H1 description
6. Commit both the image AND the prompt — reproducers are first-class artifacts in this repo

# See Also

- [docs/skill-anatomy.md](docs/skill-anatomy.md) — Skill structure specification
- [docs/getting-started.md](docs/getting-started.md) — Setup for any runtime
- [CONTRIBUTING.md](CONTRIBUTING.md) — Contribution guidelines

# Orca multi-agent skills

**All multi-agent skills in this repo are built on Orca orchestration** (runtime + the `orchestration` skill from the Orca CLI). They are strategy layers on that grammar; they do not replace it and do not substitute in-process subagents.

`clean-sweep` and `spec-to-ship` require the **Orca** runtime and the companion **`orchestration` skill shipped with the Orca CLI** — it is **not** published under `skills/` in this repository. They are independent peers (neither skill depends on the other).

# Review ownership and routing

One owner per review concern — never "and/or". Selection rule:

| Change / need                                          | Owner                | Never |
|---------------------------------------------------------|----------------------|-------|
| Standards + Spec of a diff/PR (Matt path)                | `review-matrix`      | Not run again inside gstack-ship-fleet |
| Production-risk axes (SQL, authz, LLM trust, side effects) | `review-prod-fleet` | Never fixes; report-only |
| Pre-ship umbrella (tests + review army + changelog + PR) | `gstack-ship-fleet` via gstack `/ship` | Never runs its OWN duplicate test/review pass — missing/stale evidence routes to the owning review fleet, or falls back to /ship's built-in army |
| Security deep audit (OWASP/STRIDE)                       | `cso-fleet`          | Not folded into review-matrix's security-lite when a real audit is wanted |

**Finding schema** (every review fleet emits findings in this JSON shape so downstream skills
can consume instead of re-scan):

```json
{"id": "RM-003", "axis": "standards|spec|test-adequacy|sql|authz|llm-trust|side-effects|security",
 "file": "src/x.ts", "line": 42, "severity": "P0|P1|P2",
 "summary": "...", "reviewed_sha": "<commit reviewed>", "report_path": "docs/reviews/..."}
```

**Reviewed-SHA handoff:** a consumer (merge role, gstack-ship-fleet, full-sprint-fleet) treats
review evidence as FRESH only when `reviewed_sha` equals the branch HEAD it is about to act on.
Stale → route back to the owning fleet, don't re-review ad hoc.

# Matt coding-flow invariant

Coding workflows exit through **`/to-spec` → `/to-tickets` → `/implement`** — a frozen spec is
the canonical fixed point for ticket acceptance criteria and Spec review. `matt-ship`,
`wayfinder-fleet`, `architecture-sprint`, and `spec-issue-fleet` all pass through it.
Non-coding exceptions (no spec freeze required): `content-wayfinder` (writing),
`research-then-grill` (research), `office-hours-async` (decision prep), report-only fleets.

# One worker-playbook router per worker (hard rule)

Autonomous missions draw worker methodology from upstream packs — mattpocock/skills,
garrytan/gstack, and addyosmani/agent-skills. Each of those ships its OWN router/meta-skill,
and they fight when co-mounted (clashing command names, competing routing, conflicting TDD
philosophies — Addy folds REFACTOR into the TDD loop, Matt puts it in review). A worker TASK
therefore loads exactly ONE pack's playbooks. Cross-pack cherry-picking is fine at the
mission level (one worker runs Matt triage, another runs Addy security-and-hardening); it is
never fine inside a single worker. Missions state which pack a worker uses in the dispatched
TASK.

# Runtime dependency matrix

| Skill (or group)                          | Needs Orca | Needs gstack | Needs Matt skills | Needs in-pack peers |
|--------------------------------------------|------------|--------------|-------------------|---------------------|
| Matt×Orca group (matt-ship, wayfinder-fleet, design-it-thrice, review-matrix, triage-to-fleet, diagnose-swarm, architecture-sprint, research-then-grill, adversarial-ticket, content-wayfinder, model-jury, ready-agent-drain) | yes | no | yes (worker playbooks) | architecture-sprint → design-it-thrice, matt-ship; triage-to-fleet → ready-agent-drain |
| Gstack fleet group (gstack-ship-fleet, qa-fleet, cso-fleet, autoplan-fleet, review-prod-fleet, health-fleet, docs-fleet, canary-fleet, benchmark-fleet, retro-cron, ios-qa-fleet, office-hours-async, design-shotgun-fleet) | yes | yes (worker methodology) | no | none |
| `investigate-fleet`                        | yes | yes | yes (`/tdd`)      | none |
| `spec-issue-fleet`                         | yes | yes (`/spec`) | yes (ticketing) | matt-ship phases |
| `full-sprint-fleet`                        | yes | yes | yes | composes office-hours-async, autoplan-fleet, matt-ship / wayfinder-fleet / spec-to-ship, review-prod-fleet, review-matrix, qa-fleet, cso-fleet, gstack-ship-fleet, canary-fleet, docs-fleet |
| Policy (guard-policy, headless-mode)       | yes | yes (hooks / env) | no | applied to other fleets |
| Peers (clean-sweep, spec-to-ship)          | yes | no | no | none (independent peers) |
| Autonomous missions (backlog-zero, red-team-harden, flake-zero, feature-factory) | yes | one pack per worker | one pack per worker | compose in-pack fleet-ops (merge-train, fleet-doctor, gate-steward, run-blackbox, quorum, spec-decompose); worker methodology from Matt / gstack / Addy, ONE router per worker |
| Fleet ops (standing-fleet, fleet-doctor, run-blackbox, gate-steward, merge-train, quorum, spec-decompose, ephemeral-fleet, fleet-memory) | yes | no | no | compose WITH other fleets at runtime by design (each names its consumers), but run standalone; ephemeral-fleet additionally needs orca-per-workspace-env recipes |
| Utility (cloudflare-dns, namecheap-dns, fly-to-aws-migration, deep-research, terminal-poster) | no | no | no | none |
