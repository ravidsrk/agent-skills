# Announcement Copy

Drafted post copy for the dual-launch of `agent-skills` + `autonomous-fleet`. Attach `announcement-banner.jpg` to each post.

# X / Twitter (under 280 chars)

## Option A — Tight, direct

> Two open-source agent toolkits live today, sharing one design philosophy:
>
> 🟦 `agent-skills` — 5 capability skills (DNS, AWS migration, research, image gen)
> 🟧 `autonomous-fleet` — 24-skill multi-agent engineering framework
>
> github.com/ravidsrk/agent-skills
> github.com/ravidsrk/autonomous-fleet

## Option B — Story-first

> Spent the last few weeks turning my private agent toolkit into two public repos:
>
> One is reach-for-when-needed capability skills.
> The other is a portable framework for fully-autonomous coding runs.
>
> Both ship as Agent Skills packages. Both MIT.
>
> 🧵👇

## Option C — Hot-take energy

> Most "AI agent" toolkits are either too generic to be useful or too tied to one runtime.
>
> So I built two:
>
> 1. `agent-skills` → 5 production capability skills
> 2. `autonomous-fleet` → 24-skill framework, runs on Claude Code / Codex / Grok / Orca
>
> One author. Two identities. Both open-source.

# X thread (if going long)

```
1/ Shipped two open-source AI-agent repos today:

🟦 agent-skills — 5 capability skills that just work
🟧 autonomous-fleet — multi-agent engineering framework with 24 skills

Different purposes. Same philosophy: SKILL.md is the source of truth, agents read it, agents do the work.

2/ agent-skills covers:

• cloudflare-dns — migrate DNS from any registrar to Cloudflare
• fly-to-aws-migration — full Fly.io → AWS playbook
• deep-research — 8 sources in parallel (X, Reddit, HN, GitHub, YouTube, Exa…)
• terminal-poster — viral infographics via Nano Banana Pro
• ai-image-generation — best-image-per-task routing

3/ autonomous-fleet is bigger — a portable framework for fully-autonomous coding runs across orchestration tools:

🟦 1 core engine
🟪 4 runtime adapters (Claude Code, Codex, Grok, Orca)
🟧 14 mission skills (doc-sync, test-coverage, bug-batch, contract-first-build, …)

Compose into campaigns via fleet-program DAGs.

4/ Both:
• MIT licensed
• Published as Agent Skills (agentskills.io)
• Install via `npx skills add <repo-url>`
• Coming to claude-plugins-community soon

5/ Links:
github.com/ravidsrk/agent-skills
github.com/ravidsrk/autonomous-fleet

Why two repos? Different purposes deserve different identities. Same author, same craft, but the toolkits ≠ the framework.
```

# LinkedIn (longer, business-y)

> **Shipping two open-source projects today — `agent-skills` and `autonomous-fleet`.**
>
> Both come from the same problem: AI coding agents are getting good enough to do real engineering work, but the tooling layer is fragmented. Every runtime has its own format. Every "skill marketplace" has its own spec. Most published skills are demos, not production-ready.
>
> So I built two repos with different scopes:
>
> **🟦 `agent-skills` (`github.com/ravidsrk/agent-skills`)**
>
> Five battle-tested capability skills that solve specific high-value tasks:
> • `cloudflare-dns` — migrate DNS from any registrar to Cloudflare
> • `fly-to-aws-migration` — full Fly → AWS playbook
> • `deep-research` — parallel research across 8 sources
> • `terminal-poster` — viral infographic generation
> • `ai-image-generation` — best-image-per-task routing
>
> **🟧 `autonomous-fleet` (`github.com/ravidsrk/autonomous-fleet`)**
>
> A portable multi-agent engineering framework with 24 skills organized in three tiers:
> • Infrastructure (engine + program orchestrator + setup)
> • Adapters (Claude Code / Codex / Grok / Orca)
> • Missions (doc-sync, test-coverage, dependency-update, bug-batch, contract-first-build, and 9 more)
>
> Missions compose into campaigns via DAG presets like `repo-health` and `ship-with-proof`.
>
> Both are MIT-licensed, follow the agentskills.io spec, and install via `npx skills`. Both have full CI, validators, and dashboards.
>
> Most importantly: SKILL.md is the source of truth in both. The READMEs are for humans; the skills are for agents.
>
> If you're running AI coding agents in production — or want to start — these are the toolkits I wish existed six months ago.

# dev.to / Hashnode (post body)

```markdown
# Two open-source agent toolkits, one design philosophy

I just shipped two AI-agent open-source projects to GitHub. They're intentionally sibling repos with different purposes — and I want to explain why.

## The problem

AI coding agents (Claude Code, Cursor, Codex, Grok Build, Orca) are getting good enough to do real engineering work. But the tooling layer is fragmented:

- Every runtime has its own slash-command / hook / agent format.
- Every "skill marketplace" has its own spec.
- Most published skills are demos, not production-ready.
- There's no good pattern for **composing** skills into multi-step workflows.

So I built two repos.

## `agent-skills` — capability toolkit (5 skills)

Reach-for-when-needed skills that solve specific high-value tasks. Each skill is a self-contained capability with `SKILL.md` (agent-facing spec), a README (human-facing), references for progressive disclosure, and scripts.

- **`cloudflare-dns`** — migrate DNS from Namecheap (or any registrar) to Cloudflare
- **`fly-to-aws-migration`** — end-to-end Fly.io → AWS playbook
- **`deep-research`** — parallel research across X, Reddit, HN, GitHub, YouTube, Exa
- **`terminal-poster`** — generate dense viral infographics via Nano Banana Pro
- **`ai-image-generation`** — best-image-per-task routing

[`github.com/ravidsrk/agent-skills`](https://github.com/ravidsrk/agent-skills)

## `autonomous-fleet` — multi-agent engineering framework (24 skills)

A portable framework for **fully-autonomous coding runs across orchestration tools**. Three tiers:

🟦 **Infrastructure (5)** — the engine, the umbrella entry point, the program orchestrator, setup, and the discipline layer

🟪 **Adapters (5)** — `claude-code`, `codex`, `grok`, `orca`, and a template for adding new runtimes. Each adapter maps the portable engine to one runtime's real commands.

🟧 **Missions (14)** — `doc-sync`, `test-coverage`, `dependency-update`, `cleanup`, `bug-batch`, `adversarial-review-and-fix`, `targeted-migration`, `design-integration`, `landing-page-convergence`, `legacy-rebuild`, `take-product-to-completion`, `contract-first-build`, `scaffold-align`, `inference-cost`.

Missions compose into campaigns via `fleet-program` DAGs. Built-in presets: `repo-health`, `ship-with-proof`, `align-then-ship`, `quality-gate`.

[`github.com/ravidsrk/autonomous-fleet`](https://github.com/ravidsrk/autonomous-fleet)

## Why two repos?

Different purposes deserve different identities. The capability toolkit and the framework are conceptually distinct artifacts — different audiences, different installation patterns, different update cadences. Keeping them separated:

- Lets capability skills (in `agent-skills`) evolve faster, with looser invariants
- Keeps the framework (`autonomous-fleet`) under stricter validation gates
- Makes the cognitive load easier — you reach for one or the other, not both at once

Visually, they're brand-distinct too: `agent-skills` is warm cream + coral (editorial, hand-crafted feel); `autonomous-fleet` is deep midnight + amber (cockpit, engineering-serious feel). Both share an amber accent as subtle sibling resemblance.

## Install both

```bash
npx skills add https://github.com/ravidsrk/agent-skills
npx skills add https://github.com/ravidsrk/autonomous-fleet
```

Both are MIT-licensed. Both follow [agentskills.io](https://agentskills.io). Both will land in the Claude Code community marketplace soon (submission packets are pre-built).

## What's next

I'm now wiring `autonomous-fleet` into a real production stack — the headless path is the next focus. If you want to follow along, watch the repos or follow me on X.

If you build with these, I want to hear about it.
```

# Hacker News title (Show HN)

> Show HN: Two open-source toolkits for AI coding agents (capability + framework)

# Hashtags (X / LinkedIn)

```
#ClaudeCode #AIAgents #OpenSource #AgentSkills #AICoding #DevTools #AnthropicSkills
```

# Tag suggestions (X mentions)

- `@AnthropicAI` (creators of Claude Code + Agent Skills spec)
- Anthropic devs from the spec team if they're active
- The agentskills.io maintainers

# Attaching the banner

The image at `announcement-banner.jpg` is **1820×980-ish, 16:9** — perfect for X and LinkedIn. It shows both repos as siblings (left half = agent-skills warm cream + coral, right half = autonomous-fleet midnight + amber, center = `+` badge in amber).
