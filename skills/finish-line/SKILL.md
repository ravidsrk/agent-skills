---
name: finish-line
description: >-
  Drives an AI-built product that has docs, specs or GitHub issues but was never finished to verified launch-readiness. Forensic audit of what actually works, a hash-locked definition of done frozen from the docs, one-item-at-a-time build loop with Playwright / Maestro visual checks, an independent verifier subagent, tamper checks that catch skipped or weakened tests, then a release candidate on a deployed preview. Runs unattended across fresh-context sessions. Use when the user says "finish this product", "take it to launch", "drive it to completion", "verify what actually works", "the AI says it's done but it isn't", "audit my half-built app", "test everything visually", "stop the hallucinated progress", or has many unfinished AI-coded products and needs to pick one and ship it.
license: MIT
compatibility: Requires git, jq, bash 3.2+ and a headless agent CLI (Claude Code by default). Web needs Node, @playwright/test, @axe-core/playwright and @playwright/cli. Mobile needs Maestro plus an Android emulator or iOS simulator. Optional gh, gitleaks, lighthouse, Docker.
metadata:
  version: "1.0.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit Glob Grep Agent
---

# Finish Line

Coding agents start products well and stall in the last 20%: closed issues stand in for working features, the agent that wrote the code also grades it, long sessions drift, and "done" means the agent said so. This skill makes completion a property of the running software, not the transcript. It freezes a definition of done from the product's own docs, works it one item at a time, and lets an item pass only with screenshots, a passing test, a verdict from a separate verifier, and a clean tamper check.

State lives in `.finish/` inside the product repo, so every session resumes where the last one stopped.

# When to use

- A product has docs (PRD, specs, implementation plan, issues) and code, but isn't launched
- An agent keeps claiming completion that the app doesn't back up
- The user wants every feature tested visually, end to end, against the docs
- Several half-built products exist and one has to be picked and shipped

# When NOT to use

- No docs or spec at all: write the PRD first, then come back
- A single bug fix or one feature: just do it
- Pure libraries or CLIs: still usable with `api` / `command` verify methods, but skip the visual parts

# Setup

Tools: `git`, `jq`, a headless agent CLI. Web: `npm i -g @playwright/cli` (repo-level Playwright installs happen in Phase 0). Mobile: Maestro (`curl -Ls "https://get.maestro.mobile.dev" | bash`) and an emulator/simulator. Recommended: Docker (real local Postgres/Redis/Mailpit/MinIO), `gh`, `gitleaks`.

Optional env, passed through to every session: `FINISH_GIT_NAME`, `FINISH_GIT_EMAIL` (commit identity), `FINISH_NO_AI_TRAILERS=1` (no AI attribution in commits/PRs).

# How to run it

| Situation | Do this |
|---|---|
| Many products, none shipped | `scripts/portfolio.sh <folder>`, then the triage prompt in `references/portfolio-triage.md`. Exactly one `FINISH-NEXT`. |
| Finish one product, unattended (recommended) | `scripts/finish.sh <repo>` — fresh agent session per loop; stops on `LAUNCH_READY`, `BLOCKED_ON_HUMAN`, a stall, the session cap, or a tamper guard. |
| You are the agent, in a live session | Read `references/protocol.md` in full and run **one session** of it in the product repo, with `FINISH_SKILL_DIR` = this skill's folder. Then stop; the next session resumes from `.finish/`. |

Never run the build loop without the protocol: the laws in its §0 are what keep the result honest.

# The workflow

| Phase | `STATUS` | What happens | Exit |
|---|---|---|---|
| 0 Audit | `AUDITING` | `scripts/scaffold.sh`; make it boot with real local infra; fill the gate; sweep for stubs and fakes; walk every documented feature and screenshot it: WORKS / PARTIAL / FAKE / BROKEN / MISSING | `AUDIT.md` committed |
| 1 Freeze | `FREEZING` | Turn the docs into `ledger.json`: P0 = stranger signs up → gets the core promise → returns and finds their data, plus launch gates. Given/When/Then criteria. `ledger.sh validate` → `ledger.sh lock` | `FREEZE` + `LEDGER.lock` committed |
| 2 Build | `BUILDING` | `ledger.sh next` → test first → smallest real fix → `verify.sh --quick` → look at it at 375×812 and 1440×900 → verifier subagent → `ledger.sh pass` or `fail` (3 strikes → `stuck`, one second round, then `blocked_human`) | nothing in scope left to work |
| 3 Release | `RELEASING` | Fresh-clone proof, full regression, Lighthouse, preview deploy, first-user pass by the verifier, `LAUNCH_REPORT.md` | `LAUNCH_READY` or `BLOCKED_ON_HUMAN` |

# Scripts

| Script | Does |
|---|---|
| `scripts/finish.sh [repo]` | Unattended runner. Env: `MAX_SESSIONS` (40), `STALL_LIMIT` (3), `CLAUDE_MODEL`, `FINISH_AGENT`. After each frozen session it re-checks the lock, the ratchet and tamper, and stops (exit 4) if the agent touched them. |
| `scripts/scaffold.sh [--web]` | Phase 0: creates `.finish/`, vendors `ledger.sh` / `tamper.sh` / `lib.sh` into `.finish/bin/`, installs `verify.sh`, the verifier agent and (web) the Playwright config + fixture. Never overwrites. |
| `.finish/bin/ledger.sh` | `validate` · `status` · `next` · `show` · `specs` · `pass` · `fail` · `stuck` · `block` · `round2` · `reopen` · `regress` · `lock` · `check`. Mutations touch only status/attempts/evidence/notes. |
| `.finish/bin/tamper.sh` | Fails on skipped/focused tests, tautologies, deleted tests, weakened specs, test-config filter edits, `n/a`'d gate stages, edited frozen files. |
| `scripts/portfolio.sh [dir]` | Offline table of every repo under a folder. |

# Human-only

Credentials, accounts, paid plans; production data; real emails/SMS/payments; DNS; app-store submission; legal text; force-push; anything irreversible outside the repo. The agent writes these to `.finish/BLOCKERS.md` and keeps going on other items. The human does the thing, changes the line's `- ` to `RESOLVED: `, and reruns.

# Common gotchas

| Gotcha | Fix |
|---|---|
| Runner exits 2 (stalled) | Three sessions without a commit. Read the last `.finish/logs/session-*.log`; usually a boot failure or a missing credential that should be a blocker. |
| Runner exits 4 (guard) | The agent edited `FREEZE`, `LEDGER.lock`, `.finish/bin/`, the ratchet, or gamed a test. Inspect `git log -p -3`; revert; rerun. |
| `ledger.sh pass` refuses | It says why: missing screenshots, no or stale verifier report, tamper failing, spec with no assertions. Fix that; never work around it. |
| Tamper false positive (e.g. a legit `exclude` change in `pyproject.toml`) | Human re-freezes: `references/ledger.md` §8. |
| Laptop sleeps mid-run | macOS: `caffeinate -i scripts/finish.sh <repo>`. |
| `--dangerously-skip-permissions` | The default runner uses it. Run in a container, VM, or a separate OS user without production credentials. |
| CI runs `verify.sh` on a shallow clone | tamper.sh needs the freeze commit: `actions/checkout` with `fetch-depth: 0`. |
| Scope creep mid-run | Ideas go to `.finish/LATER.md`. After launch: `echo P1 > .finish/SCOPE`, commit, rerun. |

# References

- `references/protocol.md` — the per-session protocol (laws, phases, decision rules). The runner sends it as the prompt.
- `references/ledger.md` — precedence, P0/P1/P2 cut, launch gates, schema, freeze and re-freeze.
- `references/verification.md` — `init.sh`, local infra, `verify.sh` commands per stack, spec rules, `playwright-cli`, tamper rules.
- `references/portfolio-triage.md` — choosing the one product to finish.
- `templates/` — `verify.sh`, `finish-verifier.md`, `e2e/` (config, fixture, example spec), `maestro/` example flow, `ledger.example.json`.
