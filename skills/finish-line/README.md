# finish-line

Takes an AI-built product that has docs and code but never shipped, and drives it to a verified launch-ready state — fully autonomously. It never asks you a question mid-run; it decides, logs the decision, and keeps going. What's left at the end is a short list of things only you can do (a key, an account, DNS, merging), each of which reopens the work by itself once it's done.

🟢 **Cost:** your agent's compute only, no API keys of its own; capped by `MAX_SESSIONS` (default 40) and stopped early after 3 sessions without progress
🟢 **Runs:** unattended, one fresh-context session per loop, resuming from `.finish/` in the repo; self-recovering (reverts gamed sessions, pauses stalled items and brings them back as research rounds, backs off on CLI errors). Every issue it finds is resolved, never deferred or handed back to you as engineering work
🟢 **Output:** a `finish-line` branch and PR, `PRODUCT.md` (what it understood your product to be, every line quoting your docs), a frozen definition of done, screenshots and a verifier report for every item, `LAUNCH_REPORT.md`

# Why it exists

The usual loop — research, docs, GitHub issues, implement issue by issue — produces products that look 90% done and never launch. The pattern is well documented:

- Agents ship the visible 80% fast; the last 20% (error states, auth edge cases, persistence, deploy) is where products stall.
- Agents declare victory early, and when pushed they game the measure: delete or skip failing tests, weaken assertions, hardcode outputs.
- Closed issues and checked boxes get treated as working features. Nobody runs the product as a user.
- Long sessions lose the plot; the agent that wrote the code is too generous grading it.
- The agent guesses what the product is — from the repo name, the dependencies, half-written code, or what apps like it usually have — and then builds and tests the wrong thing very thoroughly.

Finish Line applies what works for long-running agents: a structured feature list with pass flags, a progress file, one feature per session, end-to-end verification through a real browser, and a separate skeptical evaluator — plus mechanical guards so the definition of done can't drift and tests can't be quietly disabled. Before any of that, it writes down what the product is, using only your docs and the running app: every claim quotes its source and is checked against it, open questions are listed instead of guessed, and the verifier approves that brief against the docs before anything is frozen.

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

**Optional: companion skills.** Community packs that make the build loop sharper, each pinned to a reviewed commit:

```bash
~/.claude/skills/finish-line/scripts/companions.sh install                    # superpowers + Addy Osmani's agent-skills
~/.claude/skills/finish-line/scripts/companions.sh install mattpocock-skills gstack   # optional extras (gstack needs Bun)
~/.claude/skills/finish-line/scripts/companions.sh list                       # what's pinned and what fills which step
```

| Step | Uses, when installed |
|---|---|
| Writing the test first | superpowers `test-driven-development` (or Addy's, or Matt Pocock's `tdd`) |
| A fix that keeps failing | superpowers `systematic-debugging` (or Addy's `debugging-and-error-recovery`, Pocock's `diagnosing-bugs`, gstack `investigate`) |
| Before claiming an item passes | superpowers `verification-before-completion` |
| Self-review before the verifier | Addy's `code-review-and-quality` (or Pocock's `code-review`) |
| Phase 0 reality map | gstack's `browse` binary and read-only `qa-only` sweep |
| Release security and performance | Addy's `security-and-hardening` and `performance-optimization` (or gstack `cso`, `benchmark`) |
| Launch checklist | Addy's `shipping-and-launch` |

They help; they never decide. The packs' planning, interview, shipping and merging skills (superpowers `brainstorming`, Addy's `spec-driven-development`, gstack `ship` and `land-and-deploy`, …) are denied in every session, hooks are off, and the verifier can't use any skill. pstack is deliberately not installed: its Claude Code port routes every session through its own hook. Details: [`references/companions.md`](references/companions.md).

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
FINISH_COMPANIONS=install ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product   # install the pinned companion packs first
FINISH_COMPANIONS=off ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product       # built-in steps only
~/.claude/skills/finish-line/scripts/finish.sh --fresh ~/code/my-product    # a run misread the product: set it aside, review again from the docs
# other agent CLIs: the protocol is appended as the last argument
FINISH_AGENT="codex exec --full-auto" ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product
```

| Exit | Meaning |
|---|---|
| `0` | `LAUNCH_READY`, or `READY_FOR_OWNER` — only owner actions remain; see `.finish/OWNER_ACTIONS.md` and `.finish/LAUNCH_REPORT.md` |
| `2` | `FINISH_MAX_DRY` (9) sessions in a row committed nothing at all, not even research notes — the agent itself isn't working (CLI broken, or it can't run anything) |
| `3` | Hit `MAX_SESSIONS` — your compute budget. Nothing open was abandoned: rerun with a higher `MAX_SESSIONS` and it picks up where it stopped |
| `4` | `FINISH_MAX_TRIPS` (3) sessions had to be reverted for gaming the gate or claiming a false finish — see the Runner notes in `.finish/PROGRESS.md` |
| `5` | The agent CLI kept exiting non-zero despite backoff (auth, rate limit, crash) |

**Interactive alternative:** in Claude Code inside the repo, *"Run one Finish Line session"* — the skill loads and the agent follows [`references/protocol.md`](references/protocol.md) for one session. Scaffold installs `.claude/settings.local.json`, which pre-approves the tools the protocol uses and denies `AskUserQuestion` and plan mode, so the session runs without permission prompts or questions.

# How it stays autonomous

| Where a person used to be needed | What happens instead |
|---|---|
| Knowing what the product is | `.finish/product.json`, from your docs and the running app only: each claim quotes its source and `ledger.sh brief` checks the quote; open questions are listed as unknowns and nothing is built on them; the verifier approves the brief and the ledger against the docs before the freeze |
| Judgment calls (ambiguous spec, missing design, which library) | A fixed decision procedure; one line per decision in `.finish/DECISIONS.md` |
| Changing the definition of done | `ledger.sh amend`: additions apply at once; removals, rewording and demotions need the independent verifier's `APPROVE` against the docs, capped at 5 |
| A tamper false positive | A verifier-approved rebaseline (`ledger.sh amend --rebaseline`) |
| Missing keys, accounts, production, DNS, store listings | `ledger.sh owner` requests the exact action and a check; the independent verifier approves it (only what you alone can provide); everything else keeps moving; the item reopens itself when the check passes |
| A session that games the gate or claims a false finish | The runner reverts it with new commits (uncommitted work stashed, `.env*` never touched) and tells the next session why |
| Sessions that make no progress | The runner pauses the item as stuck and moves on; when nothing else is failing it opens the least-tried stuck item's next research round |
| A problem that won't yield | Never abandoned and never handed to you as "needs an engineer": research rounds go deeper each time — reproduce, the installed version's docs and source, others' bug reports, a minimal reproduction and `git bisect`, a different approach — logged in `.finish/research/<ID>.md`, until it passes |
| Defects found along the way (verifier, first-user pass, Lighthouse, security review) | Each becomes an `I-###` item with `ledger.sh issue`, fixed and verified like the rest; `LATER.md` only holds ideas |
| P0 done | With `FINISH_UNTIL=P1`/`P2`, the runner opens the next scope itself |
| Skill upgrades | The runner refreshes `.finish/bin/` (re-anchoring the freeze) and an unmodified verifier agent, and migrates old statuses. A run started before the checked brief existed is set aside and reviewed again from the docs (`FINISH_KEEP_RUN=1` keeps it) |
| Community skills that ask, plan or ship | Taken at their recommended option and logged (Law 9); the gated ones are denied by the session policy, and gstack runs in its no-human mode |

# Your part (none of it during the run)

1. **One product at a time.** Don't start a second until the first is done.
2. **When it ends `READY_FOR_OWNER`:** do what `.finish/OWNER_ACTIONS.md` lists (add a key to `.env.local`, log in a CLI), then rerun. Nothing to mark — each item's check reopens it.
3. **When it ends `LAUNCH_READY`:** read `.finish/LAUNCH_REPORT.md`, review the PR, merge.
4. **Early on, if you like:** read `.finish/PRODUCT.md`. If it gets your product wrong, the doc it quotes is what misled it: fix the doc and run `finish.sh --fresh`.
5. **Whenever you like:** skim `.finish/DECISIONS.md` and `.finish/evidence/INDEX.md`. You can override anything between runs ([`references/ledger.md`](references/ledger.md) §9); the run never waits for it.

# What's in `.finish/` after a run

```
.finish/
├── RUN · STATUS · SCOPE        which skill version started the run, phase, scope
├── product.json · PRODUCT.md   the brief: what the product is, every claim quoting its source
├── sources/                    raw exports of docs that live outside the repo (GitHub issues)
├── freeze/                     the verifier's review of the brief and the ledger before the freeze
├── AUDIT.md                    what actually worked on day 0
├── ledger.json                 frozen definition of done
├── FREEZE · LEDGER.lock        freeze commit + criteria hash
├── ratchet.json                assertion counts of passing specs (can only go up)
├── amendments/ · amendments.jsonl   every change to the definition of done, with its review
├── OWNER_ACTIONS.md · owner.json · owner/   what only you can do, how it's detected, and the verifier's approval
├── PROGRESS.md · DECISIONS.md · LATER.md
├── research/<ID>.md            every research round on an item that didn't yield at first
├── init.sh · verify.sh         boot + gate
├── bin/                        ledger.sh · tamper.sh · lib.sh
├── companions.json             which installed community skills fill which step (gitignored)
├── evidence/INDEX.md           committed index (screenshots and reports are gitignored)
└── LAUNCH_REPORT.md
```

# Gotchas

| Gotcha | Fix |
|---|---|
| The run got your product wrong | `finish.sh --fresh <repo>`: the old run is archived at branch `finish-line-archive/<stamp>`, one commit returns `finish-line` to your default branch, and the review starts over from the docs. Nothing is deleted, no history is rewritten. |
| After upgrading, the runner started the review over | That run predates the checked brief, so it was set aside the same way. `FINISH_KEEP_RUN=1` keeps such a run. |
| The runner uses `--dangerously-skip-permissions` | Run it in a container, VM, or a separate OS user that has no production credentials. |
| Laptop sleeps during a long run | `caffeinate -i ~/.claude/skills/finish-line/scripts/finish.sh <repo>` on macOS. |
| Uncommitted changes in the repo before a run | Stashed automatically (`git stash list`); `.env*` files are never stashed. |
| CI fails tamper on a shallow clone | `actions/checkout` with `fetch-depth: 0`. |
| Mobile flows can't find an emulator | Boot one first (`emulator -avd <name>` / `xcrun simctl boot <device>`); the agent can't install SDKs for you. |
| It ends `READY_FOR_OWNER` over a paid-API feature | Expected without a key. Add the test-mode key to `.env.local` and rerun; the item reopens by itself. |
| Your own Claude Code hooks don't fire during a run | Runner sessions turn hooks off so third-party hooks can't interfere. `FINISH_KEEP_HOOKS=1` keeps them. |
| A pack is already installed from `claude-plugins-official` | It's used as is (and auto-updates). Uninstall it, then `companions.sh install`, to get the pinned build. |
| `tamper.sh` flags a new `eslint-disable` / `@ts-ignore` | That's the floor guard. Fix the code instead; a genuine need goes through `ledger.sh amend --rebaseline`. |

# File layout

```
finish-line/
├── SKILL.md                        ← agent entry point
├── README.md                       ← this file
├── references/
│   ├── protocol.md                 ← the per-session protocol (the runner's prompt)
│   ├── ledger.md                   ← definition-of-done rules, schema, freeze, amendments
│   ├── verification.md             ← init.sh, local infra, per-stack gate commands, spec rules
│   ├── companions.md               ← community skills: slots, denied skills, session policy, pins
│   └── portfolio-triage.md         ← picking the one product to finish
├── scripts/
│   ├── finish.sh                   ← unattended runner with guards
│   ├── fresh.sh                    ← set previous runs aside and start the review over
│   ├── scaffold.sh                 ← Phase 0 setup
│   ├── ledger.sh                   ← the only way to read/change the ledger
│   ├── tamper.sh                   ← anti-gaming check
│   ├── companions.sh               ← detect / install / policy for companion skills
│   ├── lib.sh                      ← shared helpers
│   └── portfolio.sh                ← offline repo snapshot
├── templates/
│   ├── verify.sh                   ← gate template
│   ├── finish-verifier.md          ← verifier subagent (freeze, item, amendment, owner and first-user modes)
│   ├── claude-settings.local.json  ← no permission prompts or questions in interactive sessions (+ .history)
│   ├── product.example.json        ← the brief: claims with quotes, unknowns
│   ├── ledger.example.json         ← built on that brief
│   ├── e2e/                        ← playwright.config.ts · finish-fixture.ts · J-001.example.spec.ts
│   └── maestro/J-001.example.yaml
├── companions/
│   ├── catalog.json                ← packs, slots, deny lists
│   └── .claude-plugin/marketplace.json   ← finish-line-companions: every plugin pinned to a commit
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
- Companion packs, used at runtime and never vendored: [obra/superpowers](https://github.com/obra/superpowers), [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (the floor guard in `tamper.sh` follows its `constraint-driven-development`), [mattpocock/skills](https://github.com/mattpocock/skills), [garrytan/gstack](https://github.com/garrytan/gstack); and [pstack](https://github.com/michael-denyer/pstack-claude) for *inconclusive is not a pass*

# License

MIT
