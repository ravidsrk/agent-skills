# clean-sweep

An autonomous **multi-agent issue clean-sweep** for a code repository. Given a backlog of confirmed
findings (an audit doc, a review, or a triaged issue list), it drives a **one-PR-per-finding pipeline**
— build → open-PR + bot-reconcile → build-blind review → conflict-aware commit-preserving merge → cleanup
— and leaves the repo **demonstrably working end to end** behind an anti-inflation E2E gate.

🟢 **What it is.** A *coordinator* playbook. It spawns builder / reviewer / integrator / merge workers,
holds a file-ledger as its external brain, sequences the pipeline, and decides what runs next.
🔴 **What it is NOT.** The coordinator never writes code, reviews, opens PRs, or merges itself — every one
of those is dispatched to a fresh worker so the builder is never the reviewer (build-blind review is the point).
🟡 **Hard dependency.** It runs entirely on top of the **Orca** multi-agent runtime and the companion
`orchestration` skill. Portable across *repos*, **not** across agent harnesses — see Compatibility.

# When to use it

| Triggering moment | Why this skill |
|---|---|
| "clean sweep the issues", "fix everything in this audit doc", "close out this review" | This is exactly the unit of work — a confirmed finding → a merged PR. |
| A backlog of triaged findings to fix *and land*, not just list | It closes findings; a read-only review skill only lists them. |
| "find and fix every real bug and leave it green" / "autonomous fix-everything pass" | The full build → review → merge → E2E-gate loop, fanned out in bounded parallel waves. |

**Do NOT use it** for a single bug fix (just fix it), a read-only audit (this *closes* findings), or a
"hand this to another agent" ownership transfer (that's not supervised orchestration).

# How it works

```
self-orient → inventory → skeptic-triage → freeze → bootstrap integration BASE
   → per-finding pipeline (fan out, bounded parallel):
        build(codex) → open-PR + bot-reconcile(claude) → build-blind review(claude)
        → conflict-aware commit-preserving merge → worktree cleanup
   → anti-inflation E2E gate (fresh install · build/type/lint · full suite · real DB push · critical paths)
   → final report + surfaced human gates
```

Three-lane discipline keeps it honest: **Lane A** implement (most work), **Lane B** draft + gate for the
owner (legal/pricing/naming — never fabricated), **Lane 0** refuse + surface (deploy/ops — MERGE ≠ DEPLOY).

# Install

Link the folder into your agent's skills directory (symlink tracks `git pull`):

```bash
# Claude Code (user-level, cross-project)
ln -s "$(pwd)/skills/clean-sweep" ~/.claude/skills/clean-sweep

# or project-level
ln -s "$(pwd)/skills/clean-sweep" .claude/skills/clean-sweep
```

Then invoke it with `/clean-sweep`, or just say *"clean sweep the issues in this repo"* — the description
fires on real triggers. It runs its own **preflight** and stops with a clear message if Orca isn't up.

# Usage

The skill is self-orienting — point it at a repo (and a findings source if you have one) and it derives
maintainer, default branch, toolchain, build/lint/test commands, and the PR bot itself. Everything runs
against an **integration branch**; promotion to the default branch and closing the issues are surfaced as
human-owned steps (with the promotion-PR auto-close trick documented in `references/learnings.md`).

# File layout

```
clean-sweep/
├── SKILL.md                     # the coordinator playbook (loads on activation)
├── references/
│   ├── learnings.md             # hard-won operational failure→fix items — read before spawning
│   ├── pipeline.md              # per-finding state machine + ledger schema + merge ordering
│   ├── hygiene.md               # commit + secret hygiene rules
│   └── housekeeping.md          # Phase 6 post-run promotion / stale-branch reconciliation
├── scripts/
│   ├── spawn_worker.sh          # reliable dispatch (works around the paste-not-submitted bug)
│   ├── pm.py                    # tolerant parser for orchestration inbox/check JSON
│   └── preflight.py             # BASE != default-branch + deps preflight (M-5 guardrail)
└── assets/
    ├── builder_preamble.txt     # implement + regression-test role template ({{PLACEHOLDERS}})
    ├── integrator_preamble.txt  # open-PR + bot-reconcile role template
    ├── reviewer_preamble.txt    # build-blind review role template
    └── merge_preamble.txt       # conflict-aware commit-preserving merge role template
```

# Known gotchas

Captured in full in `references/learnings.md`. The ones that bite first:

| Gotcha | Fix |
|---|---|
| A dispatched `claude` worker sits idle — prompt pasted but not submitted | Send an explicit Enter after inject; verify a heartbeat. Baked into `spawn_worker.sh`. |
| A PR review bot's autofix "never converges" — pushes commits even after review PASS | Only merging stops it; freeze-check + normalize author/trailers right before merge, then merge fast. |
| Green unit tests ≠ working product | The anti-inflation E2E gate (fresh install, real DB push, critical-path assertions) — it routinely catches a build-breaker the per-PR reviews missed. |
| Fixes land but issues never auto-close | Per-finding PRs merge to a non-default branch; put every `Closes #N` in the **promotion PR** body so they auto-close on merge to the default branch. |
| Migration-number collisions across parallel fixes | Renumber the later one + update the migration journal, or it's silently skipped. |

# Compatibility

Requires the **Orca** multi-agent runtime (running, orchestration experimental feature enabled) and the
companion `orchestration` skill. Worker CLIs `codex` and `claude` on PATH; `git` + `gh`; `python3`; bash/zsh.
Optional: `gitleaks` (scoped secret scans) and a PR review bot if the repo uses one. The coordination layer
is Orca-specific; on another harness only the strategy half (`references/`, `assets/`) carries over.

# Pairs with

- [`spec-to-ship`](../spec-to-ship/) — the sibling for *greenfield* builds from a frozen spec set. Same
  coordinator / build-blind-review / PR-per-unit pipeline; `clean-sweep` fixes brownfield, `spec-to-ship`
  ships new products.

# Credits

Distilled from real autonomous multi-agent clean-sweep runs. MIT licensed.
