# Marketplace Submission Packet

Everything needed to submit both repos to the **Claude Code Community Marketplace** (`anthropics/claude-plugins-community`).

# What submission means

When Anthropic approves a submission, your plugin entry lands in [`claude-plugins-community/.claude-plugin/marketplace.json`](https://github.com/anthropics/claude-plugins-community/blob/main/.claude-plugin/marketplace.json) (2,200+ plugins as of July 2026). Users discover and install via:

```bash
/plugin marketplace add anthropics/claude-plugins-community
/plugin install autonomous-fleet@claude-community
/plugin install agent-skills@claude-community
```

CI automatically bumps the pinned SHA when you push new commits, so future updates flow through without re-submitting.

# Two submission forms (pick ONE per repo)

🟦 **Console form** (use this — works for individual authors):
https://platform.claude.com/plugins/submit

🟪 **claude.ai form** (requires Team/Enterprise org + directory admin):
https://claude.ai/admin-settings/directory/submissions/plugins/new

Both feed the same review pipeline. Use the Console form unless you already have a Team org with directory management access.

# Pre-submission checklist (already done ✅)

- ✅ Both repos have `.claude-plugin/plugin.json` at the root
  - autonomous-fleet: `2a0f7b9664fac8c19f192bac26809ee9f7360fd4`
  - agent-skills: bump to current HEAD at submission time — see [`PRE-SUBMIT.md`](./PRE-SUBMIT.md)
- ✅ Both have `SKILL.md` files following the agentskills.io spec
- 🟡 Most skills ship with a per-skill banner + install instructions in their README (see AGENTS.md → Imagery & Banners; `clean-sweep` and `terminal-poster` are documented exceptions)
- ✅ Both are MIT licensed
- ✅ Both have CI green on the submission SHA
- 🔴 **Before submitting agent-skills, run through [`PRE-SUBMIT.md`](./PRE-SUBMIT.md)** — it regenerates the pinned SHA, verifies the skill count, and guards against the "ai-image-generation" ghost-skill regression.
- 🟡 Optional pre-submit: run `claude plugin validate` locally (the review pipeline runs the same check)

# Submission packet for `autonomous-fleet`

**Repository:** https://github.com/ravidsrk/autonomous-fleet
**Pinned SHA:** `2a0f7b9664fac8c19f192bac26809ee9f7360fd4` (or whatever `main` is at submission time)
**Category:** development
**One-line pitch:** Multi-agent engineering framework for fully-autonomous coding runs. One portable engine. 4 runtime adapters. 24 skills (5 infrastructure + 5 adapters + 14 missions).

**Description** (paste into form):

> Portable multi-agent engineering framework for fully-autonomous coding runs. One tool-agnostic core engine, per-runtime adapters (Claude Code, Codex, Grok, Orca), and 14 mission skills (doc-sync, test-coverage, dependency-update, cleanup, bug-batch, adversarial-review-and-fix, targeted-migration, design-integration, landing-page-convergence, legacy-rebuild, take-product-to-completion, contract-first-build, scaffold-align, inference-cost) that compose into multi-step engineering campaigns via fleet-program DAGs.

**Marketplace entry** (ready-to-paste JSON): lives in the sibling repo at
[`ravidsrk/autonomous-fleet` → `docs/marketplace-submission/marketplace-entry.json`](https://github.com/ravidsrk/autonomous-fleet/blob/main/docs/marketplace-submission/marketplace-entry.json)
— this packet does not carry a local copy.

# Submission packet for `agent-skills`

**Repository:** https://github.com/ravidsrk/agent-skills
**Pinned SHA:** `<BUMP-TO-HEAD-AT-SUBMIT>` — refresh with `git rev-parse HEAD` immediately before opening the form (see [`PRE-SUBMIT.md`](./PRE-SUBMIT.md))
**Category:** development
**One-line pitch:** Production-grade capability skills for AI coding agents. 6 battle-tested skills covering cloud infrastructure, research, viral image generation, and autonomous multi-agent codebase clean-sweep.

**Description** (paste into form):

> Production-grade capability skills for AI coding agents. Six battle-tested skills: cloudflare-dns (migrate DNS from any registrar to Cloudflare with bulk record import and registrar nameserver flip), namecheap-dns (manage Namecheap DNS records via the XML API — handles IP-allowlist and wholesale-replace quirks), fly-to-aws-migration (end-to-end Fly.io → AWS migration playbook covering Postgres → Aurora, Machines → ECS Fargate, secrets, DNS cutover), deep-research (parallel multi-source research across X, Reddit, HackerNews, GitHub, Polymarket, YouTube, and Exa neural search), terminal-poster (dense retro-cyberpunk viral infographics via Nano Banana Pro), and clean-sweep (autonomous multi-agent issue clean-sweep — one-PR-per-finding pipeline on the Orca runtime). MIT licensed.

**Marketplace entry** (ready-to-paste JSON): see [`marketplace-entry.json`](./marketplace-entry.json)

# After submission

Approved plugins are pinned to a specific commit SHA in `claude-plugins-community` and the CI automatically bumps the pin on subsequent pushes to the source repo. The public catalog syncs nightly. Check whether your plugin is installable:

```bash
grep -i "autonomous-fleet\|agent-skills" <(curl -sL https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json)
```

There's no SLA on review time — usually within a few days. If you don't see it after a week, follow up on the form's reply thread or open an issue at `anthropics/claude-plugins-community`.

# Other marketplaces (optional)

These are smaller/independent registries — useful for discoverability but not required:

| Marketplace | Submit at | Notes |
|---|---|---|
| 🟪 **claude-plugins-official** | (curated, no application) | Anthropic picks. Don't submit. |
| 🟦 **claude-plugins-community** | platform.claude.com/plugins/submit | **Primary target** — 2,200+ plugins |
| 🟦 **Agent Skill Hub** | https://agentskillhub.dev | GitHub import via web UI |
| 🟦 **skills.re** | https://skills.re/submit | GitHub URL import |
| 🟦 **agentskillsindex.com** | https://agentskillsindex.com | Public registry |
| 🟦 **SkillsMP** | https://skillsmp.com | Manus marketplace mirror |
| 🟦 **aiskillstore/marketplace** | github.com/aiskillstore/marketplace (PR) | Security-audited mirror |

The Community marketplace is by far the highest-value submission. Everything else is nice-to-have.

# Files in this packet

- `README.md` — this file
- `PRE-SUBMIT.md` — mandatory checklist to run immediately before opening the form
- `marketplace-entry.json` — ready-to-paste marketplace.json entry for `agent-skills`
- `announcement-banner.jpg` — side-by-side banner for X/LinkedIn announcement
- `announcement-banner-prompt.txt` — Nano Banana Pro prompt used to regenerate the banner
- `announcement-copy.md` — drafted post copy for X + LinkedIn + dev.to

The autonomous-fleet marketplace entry lives in the sibling repo (see the link above); this
packet only ships the agent-skills entry.
