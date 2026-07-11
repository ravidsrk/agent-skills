# Independent review: multi-agent and fleet orchestration skills

Date: 2026-07-11  
Repository: <code>/Users/ravindra/code/agent-skills</code>  
Review mode: read-only code and packaging review; no skill implementation was changed

## 1. Executive score

**Overall: 6.0 / 10**

**Verdict:** The strategy layer has strong human gates, durable ledgers, and mostly correct Orca positioning, but the shared launcher/preflight layer and several advertised policy contracts are not reliable enough for a “production-grade” fleet release.

| Axis | Score | Summary |
|---|---:|---|
| A. Spec / packaging | 7.5 | Frontmatter and physical packaging are unusually complete, but standalone-install and dependency claims are not consistently true. |
| B. Architecture / Orca hard base | 5.0 | Most skills explicitly name Orca as the runtime; the common launcher and <code>spec-to-ship</code> still contradict the hard-base contract. |
| C. Methodology fidelity | 6.5 | The main Matt coding path is represented correctly, but review slicing and some gstack wrapper behavior do not match the upstream playbooks they invoke. |
| D. Operational safety | 5.0 | Human promotion/deploy gates are good; fail-open launching, ref-alias bypasses, raw force-push, and unconditional bypass flags remain material risks. |
| E. Duplication / gaps | 5.5 | Roles are named clearly, but review ownership is ambiguous and 96 copied helpers make drift both likely and already observable. |

### Review coverage and checks

I reviewed all 32 skills in the requested scope, including all 16 directories whose names end in <code>-fleet</code>, the four policy/scheduled wrappers, the twelve Matt×Orca skills, and the two product/audit peers. I also reviewed their READMEs, scripts, relevant references and role preambles, <code>scripts/orca-coord/</code>, the root <code>README.md</code>, and <code>AGENTS.md</code>.

The static checks were healthy:

- <code>python3 scripts/validate-skills.py</code>: all 37 repository skills valid.
- All scoped <code>name</code> values match their directory; every description is within 1–1024 characters; every scoped skill declares MIT and a non-empty compatibility field.
- Every scoped skill has <code>SKILL.md</code>, <code>README.md</code>, a banner, and a banner reproducer. No scoped empty file or empty directory was found.
- All scoped shell scripts pass <code>bash -n</code>; all Python scripts compile.
- All scoped banners are valid, distinct JPEGs at 1456×720.
- A redacted gitleaks scan found no committed secret.
- Root README skill links resolve. The validator does not, however, exercise orchestration behavior, standalone installation, copied-helper drift, or catalog dependency truthfulness.

Severity in this report means:

- **P0:** immediate destructive/security failure with no meaningful safety boundary.
- **P1:** release-blocking correctness or safety defect for a production fleet.
- **P2:** important maintainability, clarity, or coverage gap that is unlikely to cause immediate damage alone.

## 2. Fleet skill grades

The common <code>spawn_worker.sh</code> and <code>preflight.py</code> findings cap every fleet below A until the shared runtime layer is fixed.

| Fleet skill | Grade | One-line note |
|---|:---:|---|
| <code>autoplan-fleet</code> | D | The review sequence is sensible, but its promised headless AUTO_DECIDE behavior is not implemented by the gstack runtime contract it relies on. |
| <code>benchmark-fleet</code> | C | Good baseline-versus-candidate framing, but a read-only measurement fleet inherits dangerous worker flags and an unrelated PR preflight. |
| <code>canary-fleet</code> | B | Explicitly observe-only with a human rollback gate; held back mainly by the common launcher. |
| <code>cso-fleet</code> | C | Strong audit/build separation, but fix orchestration is partly delegated by analogy and inherits the unsafe common runtime. |
| <code>design-shotgun-fleet</code> | C | Preserves a human taste gate, though the orchestration contract is thin and generic. |
| <code>docs-fleet</code> | C | Sensible truthfulness/release-doc split, with the same generic and overprivileged launch surface. |
| <code>full-sprint-fleet</code> | D | Useful phase map, but it is an undeclared runtime composition of many in-pack and Matt skills despite the catalog’s standalone claim. |
| <code>gstack-ship-fleet</code> | D | Human merge/deploy gates are correct, but review and test work can be duplicated and invalidated by the later gstack <code>/ship</code> run. |
| <code>health-fleet</code> | C | Report-oriented and bounded, but read-only workers receive the same write-capable bypass command and PR preflight. |
| <code>investigate-fleet</code> | C | Strong reproduce-before-fix/RCA shape; its Matt <code>/tdd</code> dependency is missing from the advertised Track D contract. |
| <code>ios-qa-fleet</code> | C | Hardware/credential prerequisites are candid, but the safety and launch layer is still generic. |
| <code>qa-fleet</code> | B | Good report-only default, test-account boundary, and explicit fix budget; common-launch defects prevent an A. |
| <code>review-prod-fleet</code> | D | Its “do not fix” contract conflicts with the fix-first gstack <code>/review</code> skill it optionally tells a worker to run. |
| <code>spec-issue-fleet</code> | D | The flow is plausible but depends on Matt and in-pack phases not represented by its Gstack-only install track. |
| <code>triage-to-fleet</code> | B | Verification workers cannot mutate tracker state and human approval precedes coordinator mutation; a strong HITL design. |
| <code>wayfinder-fleet</code> | B | Best-in-set Matt flow and ambiguity freeze gate; still inherits helper and standalone-path problems. |

## 3. Findings

### P0

**No P0 finding.** I found no hardcoded secret, automatic production rollback, silent deployment, or unconditional merge to the default branch. The P1 findings below are nevertheless release blockers for the repository’s “production-grade” claim because they can make orchestration report success after failure or violate a declared isolation/safety boundary.

---

### P1 — A. Spec / packaging

#### A1. <code>spec-to-ship</code> has a real runtime dependency on its peer after explicitly denying one

Files:

- <code>skills/spec-to-ship/assets/integrator_preamble.txt:4</code>
- <code>skills/spec-to-ship/SKILL.md:38-49</code>
- <code>skills/spec-to-ship/README.md:90-92</code>
- <code>skills/spec-to-ship/scripts/preflight.py</code>

The integrator role says:

> “run python3 skills/clean-sweep/scripts/preflight.py”

That contradicts the skill’s own statement:

> “same Orca dispatch patterns as clean-sweep, without depending on that skill”

and its hard-base claim:

> “not on other skills in this pack”

The peer even ships its own <code>scripts/preflight.py</code>, so this is not a missing implementation; it is a wrong packaged path. A standalone <code>spec-to-ship</code> installation can fail or accidentally execute another installed skill’s version.

#### A2. The install matrix understates actual dependencies and does not install the dependencies its comments promise

Files:

- <code>README.md:60</code>
- <code>README.md:122-170</code>
- <code>skills/full-sprint-fleet/SKILL.md:35-39</code>
- <code>skills/spec-issue-fleet/SKILL.md:35-36</code>
- <code>skills/investigate-fleet/SKILL.md:37</code>

The catalog states:

> “Skills in this pack do not depend on each other at runtime”

but <code>full-sprint-fleet</code> directly composes <code>office-hours-async</code>, <code>autoplan-fleet</code>, <code>matt-ship</code>/<code>wayfinder-fleet</code>, <code>spec-to-ship</code>, both review fleets, QA, CSO, ship, canary, and docs. <code>spec-issue-fleet</code> invokes Matt ticketing and <code>matt-ship</code> phases. <code>investigate-fleet</code> invokes Matt <code>/tdd</code>.

Track D advertises only Orca + gstack, and its quick-start loop only symlinks the wrapper skills; it does not install gstack or Matt. Track C’s “also: npx skills add…” is a comment, not an executed command. A user following the quick start can therefore obtain an apparently installed fleet that cannot run its named worker methods.

#### A3. <code>matt-ship</code> gives repository-root helper paths as the primary installed instructions

File: <code>skills/matt-ship/SKILL.md:54,82,115,154-162</code>

The main process tells a worker to call <code>scripts/orca-coord/preflight.py</code>, <code>spawn_worker.sh</code>, and <code>pm.py</code>. Those paths exist only in a checkout of this repository. A normal per-skill symlink/install contains the local <code>skills/matt-ship/scripts/</code> copies instead. The skill mentions local copies later, but the executable path in the actual flow is still a phantom for a standalone install.

---

### P1 — B. Architecture / Orca hard base

#### B1. The shared worker launcher fails open, mutates DAG state, and uses a stale launch sequence

Files:

- <code>scripts/orca-coord/spawn_worker.sh:20-48</code>
- Every scoped <code>skills/*/scripts/spawn_worker.sh</code> copy
- Current installed Orca authority: <code>~/.agents/skills/orchestration/SKILL.md:81-95,116-120,171-185</code>

All 33 copies use <code>set -u</code>, not a fail-fast shell mode. The script creates a terminal, parses output, suppresses errors from later Orca calls, unconditionally runs:

> “orca orchestration task-update --id "$task" --status ready”

then dispatches, manually sends Enter, retries more Enter presses based on heartbeat visibility, and finally prints a handle. Because the last command is an <code>echo</code>, failed create/wait/dispatch/send operations can still produce exit 0 and an apparently valid result such as a missing handle or heartbeat.

The forced <code>ready</code> transition can bypass dependency-derived DAG readiness. The current Orca grammar waits for <code>tui-idle</code> and dispatches with injection; it does not prescribe repeated unconditional Enter presses. A heartbeat means “alive,” not “the prompt was accepted,” so it is not a sound trigger for terminal input.

This is the most important defect in the repository because nearly every scoped workflow delegates correctness to this helper.

#### B2. <code>spec-to-ship</code> permits the exact in-process/harness substitution its hard base forbids

Files:

- <code>skills/spec-to-ship/SKILL.md:47-65,117-146</code>
- <code>skills/spec-to-ship/references/pipeline.md:3,112-137</code>

The hard base is explicit:

> “built on Orca orchestration … not on in-process subagents”

but the same skill says a coordinator may be:

> “Orca or similar”

and its lightweight mode says:

> “parallel subagents build the new files, the coordinator owns the shared spine”

The pipeline reinforces this with:

> “Adapt verbs to your harness; the shape is the point.”

That is not a harmless portability note: it replaces the required runtime’s worktrees, durable dispatches, gates, and <code>worker_done</code> lifecycle with a different coordination mechanism. The lightweight pipeline also has a single integrator open, review, and merge PRs, while the main skill promises a separate build-blind reviewer and reviewed-SHA merge invariant. The architecture contract is therefore internally inconsistent.

#### B3. <code>headless-mode</code> describes a prompt convention, not the runtime mode gstack actually reads

Files:

- <code>skills/headless-mode/SKILL.md:33-47</code>
- <code>skills/autoplan-fleet/SKILL.md:35-41</code>
- Upstream gstack session detector: [bin/gstack-session-kind](https://github.com/garrytan/gstack/blob/main/bin/gstack-session-kind)

The wrapper injects:

> “SESSION_KIND=headless … AUTO_DECIDE: choose the recommended option”

Current gstack detects headless execution from <code>GSTACK_HEADLESS</code>, not from prose in a task preamble. More importantly, gstack’s actual <code>headless</code> mode blocks when a question cannot be asked; its <code>spawned</code> mode is the one that auto-selects a recommended answer. Therefore the wrapper’s named mode both fails to activate and advertises the opposite fallback behavior.

<code>autoplan-fleet</code> depends on this promise for autonomous reviewer decisions, so it can block at precisely the point the wrapper claims it will continue.

#### B4. <code>guard-policy</code> is advisory text while presenting itself as enforcement

Files:

- <code>skills/guard-policy/SKILL.md:31-50</code>
- Every copied worker launcher
- Current installed gstack authorities: <code>~/.claude/skills/gstack/guard/SKILL.md</code>, <code>~/.claude/skills/gstack/freeze/SKILL.md</code>

The wrapper writes <code>docs/guard-policy.md</code> and appends policy prose to task/preamble text. It does not install or invoke the gstack guard/freeze hooks, establish an enforced path boundary, or alter the worker command. Real gstack freeze enforcement uses hook state and denies out-of-bound edits. Here, workers still launch with approval/sandbox bypass flags.

Calling this “guard-policy” and saying it applies to all fleet skills creates a false safety signal. A model may comply, but the policy is not a control boundary.

#### B5. Peer decision-gate guidance bypasses the current Orca gate protocol

Files:

- <code>skills/spec-to-ship/SKILL.md:160-161</code>
- <code>skills/spec-to-ship/references/gotchas.md:34-46</code>
- <code>skills/spec-to-ship/references/pipeline.md:137</code>
- <code>skills/clean-sweep/references/learnings.md:241-247</code>
- Current installed Orca authority: <code>~/.agents/skills/orchestration/SKILL.md:81-95,126-138</code>

The peer docs direct coordinators to answer blocking asks by typing into the terminal:

> “Answer worker decision-gates via terminal-send … not only the reply channel”

The current Orca contract uses <code>orca orchestration ask</code> to create the decision gate and <code>orca orchestration reply</code> to resolve it. Terminal injection bypasses the durable gate reply/provenance path and can type into a terminal that has moved to a different state. If an older Orca defect required this workaround, it needs a version check and a narrowly scoped fallback rather than being the primary protocol.

---

### P1 — C. Methodology fidelity

#### C1. <code>review-matrix</code> and <code>matt-ship</code> invoke unsupported “axis-only” variants of Matt code review

Files:

- <code>skills/review-matrix/SKILL.md:48-69</code>
- <code>skills/matt-ship/SKILL.md:125-132</code>
- Upstream Matt playbook: [skills/engineering/code-review/SKILL.md](https://github.com/mattpocock/skills/blob/main/skills/engineering/code-review/SKILL.md)

The wrappers request one worker for:

> “Matt /code-review Standards only”

and another for:

> “Matt /code-review Spec only”

The current upstream <code>/code-review</code> playbook defines both axes as one invocation and spawns its own parallel reviewers; it exposes no Standards-only or Spec-only mode. A faithful worker therefore either creates nested in-process subagents and reviews both axes twice, or ignores the named playbook and invents an unsupported partial mode. Both outcomes violate the wrapper’s stated methodology/runtime split.

The axis rubrics can be delegated through Orca, but they should not be represented as modes of an upstream skill that does not have them.

#### C2. <code>architecture-sprint</code> skips <code>/to-spec</code> before tickets and implementation

Files:

- <code>skills/architecture-sprint/SKILL.md:39-49</code>
- <code>README.md:72-85</code>
- Upstream Matt overview: [mattpocock/skills README](https://github.com/mattpocock/skills/blob/main/README.md)

The repository correctly documents the coding flow as:

> “/wayfinder → /to-spec → /to-tickets → /implement”

<code>matt-ship</code> and <code>wayfinder-fleet</code> preserve that handoff. <code>architecture-sprint</code>, however, goes from survey and design/grill directly to tickets and implement. Because it is a coding workflow, the missing frozen spec is not cosmetic: ticket acceptance criteria and later Spec review lack a canonical fixed point.

#### C3. <code>review-prod-fleet</code>’s report-only promise conflicts with gstack <code>/review</code>

Files:

- <code>skills/review-prod-fleet/SKILL.md:35-49</code>
- Upstream gstack review: [review/SKILL.md](https://github.com/garrytan/gstack/blob/main/review/SKILL.md)

The wrapper offers an optional worker running the full gstack review umbrella, then says:

> “Aggregate; do not fix unless user asked”

The upstream review workflow is fix-first: it classifies findings and applies auto-fixable changes/tests as part of the review. A worker cannot faithfully load that skill and simultaneously honor this wrapper’s report-only contract. This is a methodology mismatch, not merely unclear wording.

#### C4. <code>gstack-ship-fleet</code> pre-runs work that <code>/ship</code> performs again

Files:

- <code>skills/gstack-ship-fleet/SKILL.md:33-50</code>
- Upstream gstack ship: [ship/SKILL.md](https://github.com/garrytan/gstack/blob/main/ship/SKILL.md)
- Upstream rationale: [gstack CHANGELOG](https://github.com/garrytan/gstack/blob/main/CHANGELOG.md)

The wrapper schedules a full test worker, then “gstack /review and/or review-prod-fleet / review-matrix,” then a gstack <code>/ship</code> worker. Current <code>/ship</code> already performs test/coverage and a pre-landing review army. The gstack changelog explicitly treats a separate preceding <code>/review</code> as redundant.

Worse, if <code>/ship</code> fixes anything, the earlier build-blind review result is now stale. The wrapper uses the gstack name but changes its intended unit of work without defining artifact reuse or a no-fix ship mode.

---

### P1 — D. Operational safety

#### D1. The advertised “BASE must not equal default” guard is bypassed by equivalent refs

Files:

- <code>scripts/orca-coord/preflight.py:46-59,107-117</code>
- Every scoped <code>skills/*/scripts/preflight.py</code> copy

The guard performs a raw string comparison between <code>args.base</code> and the default branch. It rejects <code>--base main --default main</code>, but accepts both:

- <code>--base origin/main --default main</code>
- <code>--base refs/remotes/origin/main --default main</code>

Both commands returned “preflight: OK” during this review. The branch-existence and merge-base checks only prove that the refs exist and share history; they do not canonicalize the commit or prove a distinct integration branch. This defeats the exact wrong-base protection the skills repeatedly advertise.

#### D2. Two isolated-design workflows create worktrees without the selected base branch

Files:

- <code>skills/design-it-thrice/SKILL.md:69-78</code>
- <code>skills/model-jury/SKILL.md:39-48</code>

Both examples use <code>orca worktree create ... --no-parent</code> without <code>--base-branch</code>. In the current CLI, <code>--no-parent</code> controls Orca lineage; it does not select the Git base. Omitting the base can place candidate work on the repository default rather than the chosen integration branch, excluding unmerged prerequisite work and making comparisons invalid.

#### D3. Every copied launcher defaults to maximum permission bypass, including read-only fleets

Files:

- <code>scripts/orca-coord/spawn_worker.sh:5-6</code>
- Every scoped <code>skills/*/scripts/spawn_worker.sh:5-6</code>
- <code>skills/clean-sweep/SKILL.md:65-72</code>

The default commands are:

> “codex --dangerously-bypass-approvals-and-sandbox”

and:

> “claude --dangerously-skip-permissions”

Only <code>clean-sweep</code> has a clear pre-run authorization ceremony for broad autonomous mutation. Read-only fleets such as benchmark, health, retro, office-hours preparation, and report-mode review get the same capability. This unnecessarily widens credential, filesystem, and command blast radius and undermines the guard-policy claim.

#### D4. Peer merge roles prescribe raw force-push and routine branch-protection bypass

Files:

- <code>skills/clean-sweep/assets/integrator_preamble.txt:9</code>
- <code>skills/clean-sweep/assets/merge_preamble.txt:12-15</code>
- <code>skills/spec-to-ship/assets/integrator_preamble.txt:9</code>
- <code>skills/spec-to-ship/assets/merge_preamble.txt:12-15</code>
- <code>skills/spec-to-ship/SKILL.md:107-111,153-156</code>
- <code>skills/guard-policy/SKILL.md:35-45</code>

The roles say “force-push” without requiring <code>--force-with-lease</code>, and <code>spec-to-ship</code> prescribes automatic <code>--admin</code> handling for a known merge trap. Raw force push can overwrite concurrent bot/human work; <code>--admin</code> bypasses branch protection rather than resolving or explicitly waiving the failing gate.

This also contradicts guard-policy’s global “never force-push” rule. The repository currently provides no executable policy for deciding which instruction wins. Promotion/deploy remains human-gated, which prevents this from being P0, but branch-level integrity is still at risk.

---

### P1 — E. Duplication / gaps

#### E1. Review ownership is not partitioned across <code>review-matrix</code>, <code>review-prod-fleet</code>, and <code>gstack-ship-fleet</code>

Files:

- <code>skills/review-matrix/SKILL.md:48-76</code>
- <code>skills/review-prod-fleet/SKILL.md:33-52</code>
- <code>skills/gstack-ship-fleet/SKILL.md:33-53</code>

The intended centers are discernible:

- <code>review-matrix</code>: Standards + Spec, optionally security/test.
- <code>review-prod-fleet</code>: SQL, AuthZ, LLM/tool trust, conditional side effects, optionally full gstack review.
- <code>gstack-ship-fleet</code>: tests, review, PR shipping.

But the optional axes erase those borders. The ship fleet says “and/or,” provides no selection rule, and then invokes <code>/ship</code>, which contains another umbrella review. Security/test can run in either review wrapper; full gstack review can run in review-prod or ship. There is no shared finding schema, reviewed-SHA handoff, or deduplication key. The likely outcome is duplicate cost followed by stale review evidence.

#### E2. Ninety-six copied helper files have already drifted and have no behavioral tests

Files:

- <code>scripts/orca-coord/{spawn_worker.sh,preflight.py,pm.py}</code>
- 32 scoped copies under <code>skills/*/scripts/</code>
- <code>scripts/validate-skills.py:66-102</code>

There are 32 local copies of each of the three coordinator helpers, plus the root canonical set. All <code>pm.py</code> files are byte-identical today, while spawn/preflight copies differ in labels and error text. Twelve Matt copies already have a malformed preflight suggestion, and the <code>spec-to-ship</code> preamble already points to the wrong peer helper. There are no tests for launch failure, DAG readiness, ref aliases, JSON noise, or standalone installed paths.

The frontmatter validator passes all of these defects because it does not inspect behavior or package references. Duplication is not only a maintainability concern here; it is the mechanism by which safety fixes will fail to reach every fleet.

---

### P2 — A. Spec / packaging

#### A4. Thirty-one launcher comments point to a nonexistent learning reference

File pattern: <code>skills/*/scripts/spawn_worker.sh:15</code>

Every scoped launcher says:

> “See references/learnings.md #23”

Only <code>clean-sweep</code> contains that file. The other 31 are phantom package references copied from the source skill.

#### A5. Catalog discovery is incomplete in <code>AGENTS.md</code>

File: <code>AGENTS.md:19-47</code>

The intent map omits 11 scoped skills that are present in the root catalog: <code>benchmark-fleet</code>, <code>canary-fleet</code>, <code>design-shotgun-fleet</code>, <code>docs-fleet</code>, <code>health-fleet</code>, <code>investigate-fleet</code>, <code>ios-qa-fleet</code>, <code>office-hours-async</code>, <code>retro-cron</code>, <code>review-prod-fleet</code>, and <code>spec-issue-fleet</code>. Because <code>AGENTS.md</code> tells agents to use its intent mapping, these skills are less discoverable than the README suggests.

#### A6. Minor compatibility/frontmatter copy errors reduce trust

Files:

- <code>skills/matt-ship/SKILL.md:9</code>
- <code>skills/wayfinder-fleet/SKILL.md:13</code>
- <code>skills/design-it-thrice/SKILL.md:11</code>

Examples include “orchestration skill (Orca CLI) skill” and duplicated “(Orca CLI)” phrases. They pass the formal validator but look generated and make dependency declarations harder to scan.

#### A7. Several wrappers inaccurately say all three bundled scripts “call Orca”

Representative file: <code>skills/review-prod-fleet/SKILL.md:55-59</code>

The repeated README/SKILL block says <code>spawn_worker.sh</code>, <code>preflight.py</code>, and <code>pm.py</code> “call Orca.” Only the spawn helper calls Orca; preflight calls Git/GitHub, and PM parses JSONL. This is minor by itself but obscures the real runtime boundary.

---

### P2 — B. Architecture / Orca hard base

#### B6. Generic role preambles do not encode many skill-specific completion contracts

File pattern: <code>skills/{gstack fleets}/assets/*_preamble.txt</code>

Large groups of wrappers reuse four nearly identical coordinator/builder/reviewer/integrator preambles. The skill-specific acceptance criteria often exist only in <code>SKILL.md</code>, while the dispatched role text focuses on generic branch/test/report behavior. Unless the coordinator embeds the full task contract every time, workers can return a structurally valid <code>worker_done</code> that has not performed the skill’s distinctive method.

This is most visible in thin wrappers such as health, docs, benchmark, and design-shotgun. It is an architecture gap because durable Orca task text—not coordinator memory—should own the completion contract.

---

### P2 — C. Methodology fidelity

#### C5. The core Matt path is correct in two places but not expressed as a repository-wide invariant

Files:

- <code>skills/matt-ship/SKILL.md:56-76</code>
- <code>skills/wayfinder-fleet/SKILL.md:44-63,118-126</code>
- <code>skills/architecture-sprint/SKILL.md:42-49</code>
- <code>skills/spec-issue-fleet/SKILL.md:35-44</code>

The repository has the right flow in its catalog and its two flagship Matt wrappers, but secondary coding workflows freely skip or splice phases. A small methodology-routing matrix would make it clear which workflows are non-coding exceptions and which must exit through spec → tickets → implement.

---

### P2 — D. Operational safety

#### D5. Read-only fleets inherit a GitHub/base preflight that is irrelevant to their work

Examples:

- <code>skills/benchmark-fleet/scripts/preflight.py</code>
- <code>skills/health-fleet/scripts/preflight.py</code>
- <code>skills/retro-cron/scripts/preflight.py</code>
- <code>skills/office-hours-async/scripts/preflight.py</code>

These preflights require <code>gh</code>, an authenticated repository, a non-default BASE, and shared Git ancestry even when the workflow is measurement, discussion preparation, or report generation. Besides causing false failures, this encourages unnecessary credentials in workers that should be least privileged.

---

### P2 — E. Duplication / gaps

#### E3. The shared mailbox parser is brittle around valid or noisy message streams

File: <code>scripts/orca-coord/pm.py:20-35</code> and all local copies

The parser silently stops on the first JSON decode problem and assumes every message contains <code>from_handle</code> and <code>payload</code>. Orca send payloads can be optional, and command output may contain non-JSON noise. A single malformed or payload-less item can therefore hide later worker messages or raise a key error. The peer references already acknowledge noisy JSON elsewhere, but this helper does not apply the same defensive parsing.

#### E4. Cross-links list neighbors but do not define handoff contracts

Examples:

- <code>skills/review-prod-fleet/SKILL.md:51-52</code>
- <code>skills/gstack-ship-fleet/SKILL.md:52-53</code>
- <code>skills/full-sprint-fleet/SKILL.md:35-52</code>

“Related” lists do not say whether the next skill consumes the same ledger, a report path, a fixed SHA, a set of finding IDs, or a new scan. This omission is what allows the review and ship overlaps to become duplicate work instead of a composable pipeline.

## 4. Top five recommended fixes

1. **Replace the copied launcher/preflight layer with one versioned, tested, fail-closed Orca adapter.** Require <code>set -euo pipefail</code>, validate every JSON result and dispatch ID, wait for <code>tui-idle</code>, never force a task to ready, remove repeated Enter injection, verify dispatch state, canonicalize refs by commit identity, and add failure-path tests. Package or generate local shims from this one source so standalone skills still work.

2. **Restore <code>spec-to-ship</code>’s declared hard boundary.** Point its preamble at its own helper, delete/clearly segregate “Orca or similar” and in-process lightweight coordination, and make the detailed pipeline preserve separate builder, integrator, build-blind reviewer, and reviewed-SHA merge roles.

3. **Make policy wrappers executable contracts.** Map headless behavior to the actual gstack/Orca session modes and environment, and have guard-policy activate real careful/freeze hooks or explicitly rename itself as advisory. Define one precedence rule for force-push, admin merge, allowed paths, and human gates.

4. **Close the branch-integrity holes.** Compare resolved commit identities for BASE/default aliases, require <code>--base-branch</code> on every worktree, use <code>--force-with-lease</code> only when explicitly justified, and make <code>--admin</code> an explicit human-approved exception rather than a routine merge-trap response.

5. **Publish dependency and review-routing matrices, then make install tracks truthful.** Declare which wrappers need Matt, gstack, in-pack peers, browser/device/deploy tooling, and which review owner runs for a given change. Let <code>review-matrix</code> own Standards/Spec, <code>review-prod-fleet</code> own production-risk axes, and <code>gstack-ship-fleet</code> either trust gstack <code>/ship</code> or consume prior reviewed-SHA artifacts without repeating them.

## 5. What is solid — keep

- **The repository generally gets the runtime/method split right.** Most scoped skills say Orca owns tasks, dispatch, gates, worktrees, and <code>worker_done</code>, while Matt or gstack supplies worker methodology. This is the correct architectural center and should remain prominent.

- **Human authority is preserved at the consequential boundaries.** Promotion to default, deploy, rollback, tracker mutation, and taste selections are usually explicit gates. <code>canary-fleet</code> is observe-only by default; <code>qa-fleet</code> is report-only unless given a fix budget; <code>triage-to-fleet</code> keeps verification workers from mutating the tracker.

- **The best flows use durable evidence rather than chat memory.** Ledgers, report paths, finding IDs, requirement traceability, <code>worker_done</code>, fixed points, and the reviewed-SHA merge invariant are all strong patterns. The peers’ insistence that “merged” is a claim to verify is exactly right.

- **Build-blind review is treated as a real isolation property.** Separate fresh reviewer terminals, reviewer/build role separation, and adversarial verification appear throughout the strongest skills. Preserve this while fixing the contradictory lightweight/integrator pipeline.

- **The primary Matt coding flow is correctly understood.** <code>matt-ship</code>, <code>wayfinder-fleet</code>, and the root README correctly route foggy work through wayfinder and coding through spec → tickets → implement, with a human freeze gate.

- **Gstack attribution is explicit.** The wrappers generally say methodology comes from gstack and runtime comes from Orca; they link installation rather than pretending to vendor the upstream playbooks.

- **Packaging hygiene is strong.** Formal frontmatter, README presence, banners, banner prompts, directory naming, and link integrity are consistent across a large set. The visual assets are valid and unique, and the main validator is fast and deterministic.

- **Secret and production safeguards are visible.** No committed secrets were found, secret scanning is mentioned in merge roles, deploy is separated from merge, and canary explicitly avoids silent rollback. These are valuable defaults worth keeping while the permission model is tightened.

## Bottom line

This repository has a better orchestration *method* than its current score suggests: thin coordinators, durable ledgers, worker completion messages, fixed-point review, and human promotion gates are strong. The score is pulled down by the executable substrate and by contracts that exist only as prose. Fix the shared Orca adapter first; it removes risk from every fleet at once. Then make dependency, policy, and review ownership claims match what the installed tools actually do.
