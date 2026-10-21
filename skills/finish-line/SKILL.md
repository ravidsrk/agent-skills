---
name: finish-line
description: >-
  Drives an AI-built product that has docs, specs or GitHub issues but was never finished to verified launch-readiness, fully autonomously — it never asks questions or waits for approval mid-run. Forensic audit of what actually works, a hash-locked definition of done frozen from the docs, one-item-at-a-time build loop with Playwright / Maestro visual checks, an independent verifier subagent that also stands in for the owner on scope changes, tamper checks that catch skipped or weakened tests, then a release candidate on a deployed preview. Every issue it finds is resolved — researched until fixed, never deferred. Can use pinned community skills (superpowers, gstack) at fixed steps. Use when the user says "finish this product", "take it to launch", "drive it to completion", "do it autonomously", "don't ask me", "verify what actually works", "the AI says it's done but it isn't", "audit my half-built app", "test everything visually", or has many unfinished AI-coded products and needs to pick one and ship it.
license: MIT
compatibility: Requires git, jq, bash 3.2+ and a headless agent CLI (Claude Code by default). Web needs Node, @playwright/test, @axe-core/playwright and @playwright/cli. Mobile needs Maestro plus an Android emulator or iOS simulator. Optional gh, gitleaks, lighthouse, Docker.
metadata:
  version: "1.3.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit Glob Grep Agent
---

# Finish Line

Coding agents start products well and stall in the last 20%: closed issues stand in for working features, the agent that wrote the code also grades it, long sessions drift, and "done" means the agent said so. This skill makes completion a property of the running software, not the transcript. It freezes a definition of done from the product's own docs, works it one item at a time, and lets an item pass only with screenshots, a passing test, a verdict from a separate verifier, and a clean tamper check.

**Fully autonomous.** No step waits for a person. The agent decides with a fixed procedure and logs every decision in `DECISIONS.md`; the independent verifier approves or rejects changes to the definition of done; the runner reverts sessions that game the gate, pauses items that stall and brings them back as research rounds, retries a failing CLI, re-checks owner actions, and accepts a finished state only when the ledger proves it. **Every issue found is resolved:** defects found anywhere become ledger items, and an item that resists is never abandoned — it returns in research rounds that go deeper each time (docs, library source, issue trackers, the web) until it passes. The only things left to the owner — keys, accounts, production, DNS, store listings, merging — are collected in `OWNER_ACTIONS.md`, each with a check that reopens the work by itself once it's done.

State lives in `.finish/` inside the product repo, so every session resumes where the last one stopped.

# When to use

- A product has docs (PRD, specs, implementation plan, issues) and code, but isn't launched
- An agent keeps claiming completion that the app doesn't back up
- The user wants it finished without being asked questions every iteration
- The user wants every feature tested visually, end to end, against the docs
- Several half-built products exist and one has to be picked and shipped

# When NOT to use

- No docs or spec at all: write the PRD first, then come back
- A single bug fix or one feature: just do it
- Pure libraries or CLIs: still usable with `api` / `command` verify methods, but skip the visual parts

# Setup

Tools: `git`, `jq`, a headless agent CLI. Web: `npm i -g @playwright/cli` (repo-level Playwright installs happen in Phase 0). Mobile: Maestro (`curl -Ls "https://get.maestro.mobile.dev" | bash`) and an emulator/simulator. Recommended: Docker (real local Postgres/Redis/Mailpit/MinIO), `gh`, `gitleaks`.

Optional env, passed through to every session: `FINISH_GIT_NAME`, `FINISH_GIT_EMAIL` (commit identity), `FINISH_NO_AI_TRAILERS=1` (no AI attribution in commits/PRs), `FINISH_UNTIL=P1|P2` (keep going past P0), `FINISH_MAX_AMENDMENTS` (5), `FINISH_COMPANIONS=auto|off|install`, `FINISH_KEEP_HOOKS=1`.

Optional companions: `scripts/companions.sh install` adds community skill packs pinned to reviewed commits — superpowers and Addy Osmani's agent-skills by default; Matt Pocock's skills and gstack on request. See *Companion skills* below.

# How to run it

| Situation | Do this |
|---|---|
| Many products, none shipped | `scripts/portfolio.sh <folder>`, then the triage prompt in `references/portfolio-triage.md`. Exactly one `FINISH-NEXT`. |
| Finish one product, unattended (recommended) | `scripts/finish.sh <repo>` — fresh agent session per loop until `LAUNCH_READY` or `READY_FOR_OWNER`. |
| You are the agent, in a live session | Read `references/protocol.md` in full and run **one session** of it in the product repo, with `FINISH_SKILL_DIR` = this skill's folder. Don't ask the user anything — decide per its §7. Then stop; the next session resumes from `.finish/`. |

Never run the build loop without the protocol: the laws in its §0 are what keep the result honest.

# The workflow

| Phase | `STATUS` | What happens | Exit |
|---|---|---|---|
| 0 Audit | `AUDITING` | `scripts/scaffold.sh`; discover usable credentials and CLI logins; make it boot with real local infra; fill the gate; sweep for stubs and fakes; walk every documented feature and screenshot it: WORKS / PARTIAL / FAKE / BROKEN / MISSING | `AUDIT.md` committed |
| 1 Freeze | `FREEZING` | Turn the docs into `ledger.json`: P0 = stranger signs up → gets the core promise → returns and finds their data, plus launch gates. Given/When/Then criteria. `ledger.sh validate` → `ledger.sh lock` | `FREEZE` + `LEDGER.lock` committed |
| 2 Build | `BUILDING` | `ledger.sh next` → test first → smallest real fix → `verify.sh --quick` → look at it at 375×812 and 1440×900 → verifier subagent → `ledger.sh pass` or `fail` (3 strikes → `stuck`, a pause → research rounds until it passes); defects found along the way → `ledger.sh issue` | nothing in scope failing or stuck |
| 3 Release | `RELEASING` | Fresh-clone proof, full regression, Lighthouse, preview deploy, first-user pass by the verifier, `LAUNCH_REPORT.md`, `ledger.sh done-check` | `LAUNCH_READY` or `READY_FOR_OWNER` |

# What replaces asking the owner

| Situation that used to need a person | Autonomous path |
|---|---|
| A judgment call (ambiguous spec, missing design, which library) | Decision procedure in protocol §7 → one line in `DECISIONS.md` → act |
| The definition of done is wrong or too big | `ledger.sh amend`: additions apply at once; anything else needs the verifier's `APPROVE` against the docs; capped |
| `tamper.sh` flags a legitimate change | `ledger.sh amend --rebaseline`, same review |
| A key, account or production step is missing | `ledger.sh owner <ID> "<action>" "<check>"`; work continues; the item reopens by itself when the check passes |
| An item won't converge | `fail` ×3 → `stuck` (a pause) → `ledger.sh round`: unlimited research rounds, each a deeper step (reproduce → primary sources → others' reports → isolate → change approach → re-scope by amendment → fresh angle), logged in `.finish/research/<ID>.md`. Never handed to the owner as "needs an engineer": `ledger.sh owner` refuses that |
| A defect turns up (verifier, first-user pass, Lighthouse, security review, while working) | `ledger.sh issue` adds it as an `I-###` item at once; fixed and verified like any item, never parked in `LATER.md` |
| A session games the gate or claims a false finish | The runner reverts it (new commits, nothing lost), tells the next session why, and continues |
| Sessions stop making progress | The runner pauses the current item as `stuck` and moves on; when nothing else is failing it opens the least-tried stuck item's next research round |
| P0 is done | `FINISH_UNTIL=P1` makes the runner open the next scope itself |

# Companion skills

Installed community skills help at named protocol steps — superpowers' TDD, debugging and verification-before-completion; Addy Osmani's review, security, performance and launch checklists; gstack's browser and read-only QA, security and benchmark skills; Matt Pocock's `tdd`, `diagnosing-bugs` and `code-review` as fallbacks. `companions.sh detect` writes `.finish/companions.json` (slot → exact skill name) and the session invokes each only at its step (protocol §2.2, Law 9). They never decide anything: the ledger, the gate, tamper and the verifier do. Every runner session runs under a policy that denies each pack's asking, planning, publishing and merging skills, turns hooks off, and puts gstack in its no-human mode; the verifier has no Skill tool and skips CLAUDE.md. Details, pins and licenses: `references/companions.md`.

# Scripts

| Script | Does |
|---|---|
| `scripts/finish.sh [repo]` | Autonomous runner. Env: `MAX_SESSIONS` (40), `STALL_LIMIT` (3), `FINISH_UNTIL` (P0), `FINISH_MAX_TRIPS` (3), `FINISH_BACKOFF` (60), `FINISH_OWNER_CHECK_TIMEOUT` (60), `FINISH_MAX_DRY` (9), `FINISH_COMPANIONS` (auto), `FINISH_KEEP_HOOKS`, `CLAUDE_MODEL`, `FINISH_AGENT`. Every session runs under the companion policy (`--settings`). One runner per repo (lock in `.git/`). Exit 0 `LAUNCH_READY`/`READY_FOR_OWNER` · 2 the agent commits nothing at all · 3 session cap · 4 too many reverted sessions · 5 agent CLI keeps failing. |
| `scripts/companions.sh` | `detect` · `show` · `policy [--runner]` · `settings` · `install [pack…]` · `list`. Finds installed community packs and fills the protocol's companion slots; builds the deny-and-no-hooks policy every session runs under; installs packs pinned by commit SHA from `companions/` (finish-line's own marketplace). |
| `scripts/scaffold.sh [--web]` | Phase 0: creates `.finish/`, vendors `ledger.sh` / `tamper.sh` / `lib.sh` into `.finish/bin/`, installs `verify.sh`, the verifier agent, `.claude/settings.local.json` (no permission prompts, questions or plan mode in interactive sessions) and (web) the Playwright config + fixture. Never overwrites. |
| `.finish/bin/ledger.sh` | `validate` · `status` · `next` · `show` · `specs` · `pass` · `fail` · `stuck` · `round` · `issue` · `open` · `reopen` · `regress` · `owner` · `owner-check` · `done-check` · `amend` · `migrate` · `state` · `run-commands` · `lock` · `check`. Mutations touch only status/attempts/evidence/notes; a verdict is bound to the code `STATE` it checked. |
| `.finish/bin/tamper.sh` | Fails on skipped/focused tests, tautologies, deleted tests, weakened specs, test-config filter or coverage-threshold edits, new lint/type/coverage/scanner suppression comments, grown scanner ignore files, any post-freeze change to `verify.sh`, edited frozen files. |
| `scripts/portfolio.sh [dir]` | Offline table of every repo under a folder. |

# Common gotchas

| Gotcha | Fix |
|---|---|
| Runner exits 0 with `READY_FOR_OWNER` | Do what `.finish/OWNER_ACTIONS.md` lists (add a key, log in a CLI), rerun. No marking needed; the checks reopen the items. |
| Runner exits 4 | Three sessions had to be reverted. `.finish/PROGRESS.md` has a Runner note for each; look for the pattern. |
| Runner exits 2 | `FINISH_MAX_DRY` (9) sessions in a row committed nothing, not even research notes — the agent itself isn't working (its CLI, or it can't run at all). Read the last `.finish/logs/session-*.log`. |
| Runner exits 3 with items unresolved | They weren't abandoned: rerun with a higher `MAX_SESSIONS`; `.finish/research/` has every round so far. |
| Runner exits 5 | The agent CLI itself kept failing (auth, rate limit) even with backoff. Fix the CLI, rerun. |
| `ledger.sh pass` refuses | It says why: missing screenshots, no PASS report, code changed since the verifier's `STATE`, tamper failing, spec with no assertions. Fix that; never work around it. |
| Uncommitted changes before a run | The runner stashes them (never `.env*` files) — `git stash list`. |
| Laptop sleeps mid-run | macOS: `caffeinate -i scripts/finish.sh <repo>`. |
| `--dangerously-skip-permissions` | The default runner uses it. Run in a container, VM, or a separate OS user without production credentials. |
| A companion skill wants to ask, plan or ship | Law 9: take its recommended option and log it; its gated skills are denied by the session policy anyway. |
| Your own hooks don't fire during a run | Runner sessions turn hooks off. `FINISH_KEEP_HOOKS=1` keeps them. |
| CI runs `verify.sh` on a shallow clone | tamper.sh needs the freeze commit: `actions/checkout` with `fetch-depth: 0`. |

# References

- `references/protocol.md` — the per-session protocol (laws, phases, decision procedure, owner actions). The runner sends it as the prompt.
- `references/ledger.md` — precedence, P0/P1/P2 cut, launch gates, schema, freeze, amendments.
- `references/verification.md` — `init.sh`, local infra, `verify.sh` commands per stack, spec rules, `playwright-cli`, tamper rules.
- `references/portfolio-triage.md` — choosing the one product to finish.
- `references/companions.md` — which community skills are used at which step, which are denied and why, the session policy, pins, licenses, limits.
- `companions/` — `catalog.json` (packs, slots, deny lists) and `.claude-plugin/marketplace.json` (finish-line's marketplace, every plugin pinned to a commit).
- `templates/` — `verify.sh`, `finish-verifier.md` (+ `finish-verifier.history`: hashes of shipped versions, so the runner only refreshes unmodified copies), `claude-settings.local.json` (+ `.history`, so only finish-line's own copy is ever merged into), `e2e/` (config, fixture, example spec), `maestro/` example flow, `ledger.example.json`.
