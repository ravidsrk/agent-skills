# finish-line

Takes an AI-built product that has docs and code but never shipped, and drives it to a verified launch-ready state — fully autonomously. It never asks you a question mid-run; it decides, logs the decision, and keeps going. What's left at the end is a short list of things only you can do (a key, an account, DNS, merging), each of which reopens the work by itself once it's done.

🟢 **Cost:** your agent's compute only, no API keys of its own; capped by `MAX_SESSIONS` (default 40) and stopped early after 3 sessions without progress
🟢 **Runs:** unattended, one fresh-context session per loop, resuming from `.finish/` in the repo; self-recovering (reverts gamed sessions, parks stalled items, backs off on CLI errors)
🟢 **Output:** a `finish-line` branch and PR, a frozen definition of done, screenshots and a verifier report for every item, `LAUNCH_REPORT.md`

# Why it exists

The usual loop — research, docs, GitHub issues, implement issue by issue — produces products that look 90% done and never launch. The pattern is well documented:

- Agents ship the visible 80% fast; the last 20% (error states, auth edge cases, persistence, deploy) is where products stall.
- Agents declare victory early, and when pushed they game the measure: delete or skip failing tests, weaken assertions, hardcode outputs.
- Closed issues and checked boxes get treated as working features. Nobody runs the product as a user.
- Long sessions lose the plot; the agent that wrote the code is too generous grading it.

Finish Line applies what works for long-running agents: a structured feature list with pass flags, a progress file, one feature per session, end-to-end verification through a real browser, and a separate skeptical evaluator — plus mechanical guards so the definition of done can't drift and tests can't be quietly disabled.

# When to use it

- *"Finish this product"* / *"take it to launch"* / *"drive it to completion"*
- *"Verify what actually works"* / *"the AI says it's done but it isn't"*
- *"Test everything visually against the docs"*
- *"I have ten half-built apps — pick one and ship it"*

# Install

```bash
git clone https://github.com/ravidsrk/agent-skills.git
ln -sfn "$(pwd)/agent-skills/skills/finish-line" ~/.claude/skills/finish-line
```

Tools (macOS shown; use your package manager on Linux):

```bash
brew install jq gh gitleaks          # jq is required; gh and gitleaks recommended
gh auth login
npm install -g @playwright/cli        # token-efficient browser driving for the agent
# Mobile apps only:
curl -Ls "https://get.maestro.mobile.dev" | bash   # plus Android Studio emulator / Xcode simulator
# Real local infra (Postgres, Redis, Mailpit, MinIO): Docker Desktop or OrbStack
```

Per-repo pieces — `@playwright/test`, `@axe-core/playwright`, the Playwright config and fixture, the verifier subagent — are installed by the agent in Phase 0.

# Usage

**1. Pick one product** (if you have several):

```bash
~/.claude/skills/finish-line/scripts/portfolio.sh ~/code
```

Then paste the triage prompt from [`references/portfolio-triage.md`](references/portfolio-triage.md) into an agent session in `~/code`. It produces exactly one `FINISH-NEXT`.

**2. Finish it, unattended:**

```bash
export FINISH_GIT_NAME="Your Name" FINISH_GIT_EMAIL="you@example.com"   # optional commit identity
export FINISH_NO_AI_TRAILERS=1                                           # optional: no AI attribution lines
~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product

# options
MAX_SESSIONS=60 CLAUDE_MODEL=opus ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product
FINISH_UNTIL=P2 ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product     # don't stop at P0: finish everything in the docs
# other agent CLIs: the protocol is appended as the last argument
FINISH_AGENT="codex exec --full-auto" ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product
```

| Exit | Meaning |
|---|---|
| `0` | `LAUNCH_READY`, or `READY_FOR_OWNER` — only owner actions remain; see `.finish/OWNER_ACTIONS.md` and `.finish/LAUNCH_REPORT.md` |
| `2` | No progress possible: sessions keep making no commits and there's nothing left to park — usually the app can't boot |
| `3` | Hit `MAX_SESSIONS` |
| `4` | `FINISH_MAX_TRIPS` (3) sessions had to be reverted for gaming the gate or claiming a false finish — see the Runner notes in `.finish/PROGRESS.md` |
| `5` | The agent CLI kept exiting non-zero despite backoff (auth, rate limit, crash) |

**Interactive alternative:** in Claude Code inside the repo, *"Run one Finish Line session"* — the skill loads and the agent follows [`references/protocol.md`](references/protocol.md) for one session. Scaffold installs `.claude/settings.local.json`, which pre-approves the tools the protocol uses and denies `AskUserQuestion` and plan mode, so the session runs without permission prompts or questions.

# How it stays autonomous

| Where a person used to be needed | What happens instead |
|---|---|
| Judgment calls (ambiguous spec, missing design, which library) | A fixed decision procedure; one line per decision in `.finish/DECISIONS.md` |
| Changing the definition of done | `ledger.sh amend`: additions apply at once; removals, rewording and demotions need the independent verifier's `APPROVE` against the docs, capped at 5 |
| A tamper false positive | A verifier-approved rebaseline (`ledger.sh amend --rebaseline`) |
| Missing keys, accounts, production, DNS, store listings | `ledger.sh owner` records the exact action and a check; everything else keeps moving; the item reopens itself when the check passes |
| A session that games the gate or claims a false finish | The runner reverts it with new commits (uncommitted work stashed, `.env*` never touched) and tells the next session why |
| Sessions that make no progress | The runner parks the item as stuck and moves on |
| P0 done | With `FINISH_UNTIL=P1`/`P2`, the runner opens the next scope itself |
| Skill upgrades | The runner refreshes `.finish/bin/` (re-anchoring the freeze) and an unmodified verifier agent, and migrates old statuses |

# Your part (none of it during the run)

1. **One product at a time.** Don't start a second until the first is done.
2. **When it ends `READY_FOR_OWNER`:** do what `.finish/OWNER_ACTIONS.md` lists (add a key to `.env.local`, log in a CLI), then rerun. Nothing to mark — each item's check reopens it.
3. **When it ends `LAUNCH_READY`:** read `.finish/LAUNCH_REPORT.md`, review the PR, merge.
4. **Whenever you like:** skim `.finish/DECISIONS.md` and `.finish/evidence/INDEX.md`. You can override anything between runs ([`references/ledger.md`](references/ledger.md) §9); the run never waits for it.

# What's in `.finish/` after a run

```
.finish/
├── STATUS · SCOPE              phase and scope
├── AUDIT.md                    what actually worked on day 0
├── ledger.json                 frozen definition of done
├── FREEZE · LEDGER.lock        freeze commit + criteria hash
├── ratchet.json                assertion counts of passing specs (can only go up)
├── amendments/ · amendments.jsonl   every change to the definition of done, with its review
├── OWNER_ACTIONS.md · owner.json   what only you can do, and how it's detected
├── PROGRESS.md · DECISIONS.md · LATER.md
├── init.sh · verify.sh         boot + gate
├── bin/                        ledger.sh · tamper.sh · lib.sh
├── evidence/INDEX.md           committed index (screenshots and reports are gitignored)
└── LAUNCH_REPORT.md
```

# Gotchas

| Gotcha | Fix |
|---|---|
| The runner uses `--dangerously-skip-permissions` | Run it in a container, VM, or a separate OS user that has no production credentials. |
| Laptop sleeps during a long run | `caffeinate -i ~/.claude/skills/finish-line/scripts/finish.sh <repo>` on macOS. |
| Uncommitted changes in the repo before a run | Stashed automatically (`git stash list`); `.env*` files are never stashed. |
| CI fails tamper on a shallow clone | `actions/checkout` with `fetch-depth: 0`. |
| Mobile flows can't find an emulator | Boot one first (`emulator -avd <name>` / `xcrun simctl boot <device>`); the agent can't install SDKs for you. |
| It ends `READY_FOR_OWNER` over a paid-API feature | Expected without a key. Add the test-mode key to `.env.local` and rerun; the item reopens by itself. |

# File layout

```
finish-line/
├── SKILL.md                        ← agent entry point
├── README.md                       ← this file
├── references/
│   ├── protocol.md                 ← the per-session protocol (the runner's prompt)
│   ├── ledger.md                   ← definition-of-done rules, schema, freeze, amendments
│   ├── verification.md             ← init.sh, local infra, per-stack gate commands, spec rules
│   └── portfolio-triage.md         ← picking the one product to finish
├── scripts/
│   ├── finish.sh                   ← unattended runner with guards
│   ├── scaffold.sh                 ← Phase 0 setup
│   ├── ledger.sh                   ← the only way to read/change the ledger
│   ├── tamper.sh                   ← anti-gaming check
│   ├── lib.sh                      ← shared helpers
│   └── portfolio.sh                ← offline repo snapshot
├── templates/
│   ├── verify.sh                   ← gate template
│   ├── finish-verifier.md          ← verifier subagent (item, amendment and first-user modes)
│   ├── claude-settings.local.json  ← no permission prompts or questions in interactive sessions
│   ├── ledger.example.json
│   ├── e2e/                        ← playwright.config.ts · finish-fixture.ts · J-001.example.spec.ts
│   └── maestro/J-001.example.yaml
└── assets/banner-prompt.txt
```

# Pairs with

- [`deep-research`](../deep-research/) — evidence for the PRD before there's anything to finish
- [`cloudflare-dns`](../cloudflare-dns/) / [`namecheap-dns`](../namecheap-dns/) — the DNS step on the human launch checklist
- [ravidsrk/orca-fleet](https://github.com/ravidsrk/orca-fleet) — hand `references/protocol.md` to a coordinator as the directive; keep the verifier a separate agent

# Credits

- Anthropic Engineering — [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) (feature list with pass flags, progress file, one feature per session, browser-verified completion) and [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps) (separate skeptical evaluator driving the app with Playwright)
- The Ralph Wiggum loop technique — keep iterating against a completion promise
- [dunnit](https://pypi.org/project/dunnit/) — the idea of a tamper-evident definition of done

# License

MIT
