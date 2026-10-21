# Companion skills — using community packs without losing the guarantees

Finish Line can call well-known community skills at specific steps of the protocol: a TDD discipline while writing the test, a root-cause method when a fix keeps failing, a review checklist before the verifier, security and performance reviews before release. They are **optional and never in charge**. The ledger, `verify.sh`, `tamper.sh` and the verifier still decide what is done, and the runner still reverts any session that games them.

The rule that makes this safe is the same one the autonomy-minded packs already follow informally (superpowers' subagent-driven development, pstack's *never block on the human*, gstack's spawned mode): take the recommended option, log it, and hand anything irreversible to the owner. Protocol Law 9 states it for every companion.

## What gets used, and where

`scripts/companions.sh detect` fills each **slot** with the first candidate that is installed, enabled and model-invocable. The session reads `.finish/companions.json` (`companions.sh show`) and invokes a slot's skill with the Skill tool, by its exact name, at its step only. An empty slot means the built-in step is the whole step.

| Slot | Protocol step | Candidates, in order |
|---|---|---|
| `tdd` | §5a test first | `superpowers:test-driven-development` › `agent-skills:test-driven-development` › `mattpocock-skills:tdd` |
| `debug` | §5c/§5e a failure whose cause isn't obvious; the second attempt at the same failure | `superpowers:systematic-debugging` › `agent-skills:debugging-and-error-recovery` › `mattpocock-skills:diagnosing-bugs` › gstack `investigate` |
| `claim` | §5e before `ledger.sh pass`; §6.7 before a terminal `STATUS` | `superpowers:verification-before-completion` |
| `review` | §5e self-review of the item's changes before the verifier | `agent-skills:code-review-and-quality` › `mattpocock-skills:code-review` |
| `explore` | §3.6 read-only bug sweep for the reality map | gstack `qa-only` |
| `security` | §6.3 security review of the P0 surface | `agent-skills:security-and-hardening` › gstack `cso` |
| `perf` | §6.3 performance review from the Lighthouse JSON | `agent-skills:performance-optimization` › gstack `benchmark` |
| `launch` | §6.6 owner's launch checklist in `LAUNCH_REPORT.md` | `agent-skills:shipping-and-launch` |
| tool `browse` | §3.6 a second browser engine beside `playwright-cli` | gstack's `browse/dist/browse` binary |

Plugin skills are invoked by their namespaced name (`superpowers:systematic-debugging`); gstack's are top-level (`gstack-qa-only` when installed with `--prefix`, `qa-only` without). Detection checks that each skill's `SKILL.md` really exists and isn't `disable-model-invocation`, so a pack that renames or removes a skill just leaves the slot to the next candidate.

The verifier never uses any of them: its tool list has no Skill tool and it starts without CLAUDE.md (`omitClaudeMd: true`), so it cannot share the builder's method or be steered by what the builder wrote.

## The packs

| Pack | License | Install | Verdict |
|---|---|---|---|
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | default; pinned `v7.0.0` | The best fit: TDD that runs the full suite, four-phase root-cause debugging, and "no completion claims without fresh verification evidence". Its planning, plan-execution, worktree and branch-finishing skills are denied — they are a second orchestrator. |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | MIT | default; pinned `0.6.13` | Review, security, performance and launch checklists with no human gates. Its spec, plan, `/build`, `/ship`, interview and router skills are denied: they stop the turn for human approval. |
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | optional; pinned `v1.3.1` | `tdd`, `diagnosing-bugs` and `code-review` as fallbacks. The grilling, spec, ticket and implement skills are denied: interview-style or committing on their own. |
| [garrytan/gstack](https://github.com/garrytan/gstack) | MIT | optional (needs Bun); pinned commit `b616d6c` (1.91.173.0) | Read-only tools: the `browse` binary, `qa-only`, `cso`, `benchmark`, `investigate`. `ship`, `land-and-deploy`, `canary`, `qa` (fix mode), the `office-hours` and `plan-*` interviews and the browser-cookie/Chrome bridges are denied. The runner exports `GSTACK_SESSION_KIND=spawned`; without it gstack treats `claude -p` as a person being present, and CI as headless, where its skills report BLOCKED. |
| [pstack](https://github.com/michael-denyer/pstack-claude) (Claude Code port of Lauren Tan's Cursor pack) | MIT + two license files for imported Cursor material | not offered | Closest in philosophy, but the port installs a SessionStart hook that routes every session to `poteto-mode`, a pre-tool-use hook, and Cursor/Grok-oriented defaults. If you have it installed anyway, the runner turns hooks off and its router, PR-babysitting and approval skills are denied. |

Ideas from these packs that Finish Line adopted directly rather than calling at runtime:

- **Floor guard** (Addy Osmani's `constraint-driven-development`): `tamper.sh` fails when lint, type, coverage or scanner suppression comments grow after the freeze, when coverage thresholds change, or when a scanner's ignore file grows. "Tightening is silent, loosening is loud."
- **Independent expected values** (Matt Pocock's `tdd`): a test's expected value comes from the criterion or the docs, never from the app's own output — in protocol §5a and the verifier's item mode.
- **Inconclusive is not a pass** (pstack's poteto-mode): a check the verifier couldn't run is not met.
- **Evidence before claims** (superpowers' `verification-before-completion`): already Finish Line's Law 3; the `claim` slot adds its per-claim evidence table in-session.

## Installing

```bash
~/.claude/skills/finish-line/scripts/companions.sh install                 # superpowers + agent-skills
~/.claude/skills/finish-line/scripts/companions.sh install mattpocock-skills gstack
~/.claude/skills/finish-line/scripts/companions.sh list                    # pins, licenses, what fills what
FINISH_COMPANIONS=install ~/.claude/skills/finish-line/scripts/finish.sh ~/code/my-product   # install, then run
```

- Plugins install at user scope from **finish-line's own marketplace** (`companions/.claude-plugin/marketplace.json`, named `finish-line-companions`), where each entry pins a 40-character commit SHA. Claude Code refuses a download that doesn't match the pin, and marketplaces other than Anthropic's don't auto-update, so nothing moves under a run. A skill upgrade that bumps a pin is picked up by the next `install`, which updates the plugin in place.
- A pack already installed from another marketplace (for example `superpowers@claude-plugins-official`, which auto-updates) is kept and used as is; uninstall it first if you want the pinned build.
- gstack is fetched at its pinned commit into `~/.claude/skills/gstack` and set up with `--prefix --no-team --no-timeline-stop-hook --no-plan-tune-hooks`. An existing gstack checkout is left alone. gstack writes `.gstack/` into the product repo; scaffold and the runner gitignore it.
- Installing is never done by an agent session (Law 9): run it yourself, or let the runner do it with `FINISH_COMPANIONS=install`.

## The session policy

Every runner session gets `--settings "$(companions.sh policy --runner)"`. Flag-scope settings outrank the product repo's and the user's own, and deny rules hold even with `--dangerously-skip-permissions`:

- **Denied skills:** every pack's asking, planning, committing, publishing and merging skills, in both the namespaced form and with arguments (`Skill(superpowers:brainstorming)`, `Skill(superpowers:brainstorming *)`); gstack's in both prefixed and unprefixed form.
- **Denied commands:** merging PRs, creating releases, pushing to `main`/`master`, `npm`/`pnpm`/`yarn`/`cargo` publish, `npm version`, `twine upload`, production deploys with `vercel --prod` and `netlify deploy --prod`. Pushing the `finish-line` branch stays allowed: the protocol does it after every commit.
- **`disableAllHooks: true`:** Finish Line uses no hooks, and third-party hooks are exactly what would interfere — superpowers' and pstack's session-start routers, gstack's Stop hook, and whatever hooks the half-built product repo ships. `FINISH_KEEP_HOOKS=1` leaves them on.
- **`env`:** `GSTACK_SESSION_KIND=spawned`.

Interactive sessions get the same deny list merged into `.claude/settings.local.json` by scaffold and by the runner (`companions.sh settings`), plus `Skill` on the allow list — except gstack's unprefixed names and the hooks switch, which would otherwise reach into everything else you do in that repo. The merge only touches a file finish-line wrote and nobody changed since (a shipped template, listed in `templates/claude-settings.local.history`, or one of its own merges, recorded in `.git/finish-line.settings-owned`); your own file is left alone, with a note on how to merge the policy yourself.

After every session the runner also hashes `.claude/agents/finish-verifier.md`, `.claude/settings.json` and `.claude/settings.local.json`: a frozen session that changes any of them is reverted, and so is a session that installs a verifier the skill didn't ship. The runner snapshots these three before each session and restores them on a revert, because a gitignored one (or a gitignored `.claude/`) would survive both `git revert` and the stash.

`FINISH_COMPANIONS=off` turns the whole mechanism off (the policy still applies). With `FINISH_AGENT` set to another CLI it is off by default, since detection only knows Claude Code's plugins and skill folders.

## Limits

- **Auto-triggering is unreliable in `claude -p`** (measured as low as 0%), which is why slots name exact skills and the protocol says when to invoke them.
- **`--bare`.** Claude Code says bare mode will become the default for `-p`. It skips plugins, skills, hooks and CLAUDE.md, so every companion and the `.claude/agents/` verifier would disappear without an error, and it authenticates only with `ANTHROPIC_API_KEY`, never OAuth. The runner doesn't use it; when the default changes, the runner will need `--plugin-dir`, `--add-dir` and `--agents`.
- **Not verified:** whether `disableAllHooks` also covers hooks a skill declares in its own frontmatter (none of the slot skills do); whether gstack's `$B responsive` presets match 375×812 and 1440×900 (use `playwright-cli` for those).
- **Mobile:** no pack covers Maestro; the mobile path is Finish Line's own.

## Adding or bumping a pack

1. Read the skills you want to use and grep them for human gates (`ask the user`, `approval`, `wait for`, `AskUserQuestion`, `STOP YOUR TURN`). Prefer skills that check work over skills that plan or ship it.
2. Pin it: add or update the entry in `companions/.claude-plugin/marketplace.json` with a **commit** SHA (`git rev-parse HEAD` in a clone at the tag — for an annotated tag, not the tag object's SHA), or `sha`/`version` under the pack in `companions/catalog.json` for a git-installed pack.
3. In `catalog.json`: the pack's `deny` list (everything that asks, plans its own work, commits outside the item, publishes, deploys or merges) and its place in the slots.
4. `claude plugin validate skills/finish-line/companions`, then `companions.sh install <pack>` and `companions.sh detect` in a scratch repo.
5. Never vendor CC-BY-SA material (Trail of Bits) or Anthropic's source-available document skills into this MIT repo; reference them instead.
