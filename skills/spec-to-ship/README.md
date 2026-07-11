# spec-to-ship

Turn a **frozen spec/doc set into a shipped, verified product** in one end-to-end autonomous run. Given a
ready requirements set, a coordinator drives a fleet of AI coding agents through a strict **PR-per-task
pipeline** — THINK → PLAN(freeze) → FOUNDATION → parallel SLICES → INTEGRATION → HARDENING → e2e TEST(with
teeth) → ADVERSARIAL red-team → SHIP → REFLECT — and lands the whole product on an integration branch,
demonstrably working, behind an anti-inflation E2E gate and an adversarial refuse-surface suite.

🟢 **What it is.** A *coordinator* playbook. It spawns builder / reviewer / integrator workers, holds a
file-ledger as its external brain, sequences the pipeline, and decides what runs next.
🔴 **What it is NOT.** The coordinator never writes code, reviews, opens PRs, or merges itself — every one
of those is dispatched to a fresh build-blind worker (builder ≠ reviewer is the whole point).
🟡 **Hard dependency.** It runs on top of the **Orca** multi-agent runtime and the companion `orchestration`
skill. Portable across *specs/repos*, **not** across agent harnesses — see Compatibility.

# When to use it

| Triggering moment | Why this skill |
|---|---|
| "the docs are ready — build the whole thing", "turn this spec into a shipped product" | This is exactly the unit of work — a frozen spec → a built, verified, merged product. |
| A greenfield build to fan across many agents, not a single change | It parallelizes disjoint slices and serializes hot-file merge chains. |
| "autonomous end-to-end build from these requirements" | The full THINK→…→SHIP loop with build-blind review + verification gates. |
| A long autonomous run stalls, mis-merges, or merges to the wrong base | The gotchas encode the silent failures and how to recover. |

**Do NOT use it** for a single small change (just do it), or when the spec is still in flux (freeze it
first — the pipeline assumes a frozen plan).

# How it works

```
THINK (requirements-index + architecture) → PLAN (task graph + traceability + collision map) → FREEZE
  → FOUNDATION (serialized: scaffold · data layer · auth · seams · test harness)
  → SLICES (bounded parallel waves; hot mount-point files merge as serialized chains):
        build(worker) → open-PR + bot-reconcile(integrator) → build-blind review(reviewer)
        → conflict-aware commit-preserving merge → worktree cleanup
  → INTEGRATION → HARDENING
  → e2e TEST with teeth (public entry points · real persisted state · negative controls that red-then-restore)
  → ADVERSARIAL red-team (refuse-surface suites: cross-tenant authz, label smuggling, path traversal, …)
  → SHIP (land on integration branch) + REFLECT (traceability + runbook + backlog + promotion PR)
```

Every task advances only when six boolean gates read true **in the ledger file**: `BUILT · PR_OPEN · BUGBOT
· REVIEWED · MERGED · WT_CLEAN`. `MERGED` means *verified* — `state=MERGED` **and** the right base **and**
the change is greppable on the base branch, never a worker's word.

# Install

Drop the folder into your agent's skills directory:

```bash
# Claude Code (user-level, cross-project)
cp -R skills/spec-to-ship ~/.claude/skills/spec-to-ship

# or project-level
cp -R skills/spec-to-ship .claude/skills/spec-to-ship
```

Then invoke it with `/spec-to-ship`, or just say *"the docs are ready — build the whole product
autonomously"* — the description fires on real triggers.

# Usage

The skill is self-orienting — point it at a repo and a frozen spec set. It derives the maintainer, default
branch, toolchain, and build/lint/test commands, then runs THINK→PLAN→freeze and drives the pipeline.
Everything lands on an **integration branch**; the promotion to the default branch and any real
deploy/provisioning are surfaced as **human/OPS-owned** steps (merge ≠ deploy) — the swarm opens the
promotion PR but never self-merges it unprompted.

# File layout

```
spec-to-ship/
├── SKILL.md                     # the coordinator playbook (loads on activation)
└── references/
    ├── pipeline.md              # spawn/dispatch/review/merge mechanics + merge chains + scope discovery
    ├── verification.md          # anti-inflation E2E gate + adversarial suites + drift ratchets
    ├── gotchas.md               # the silent/expensive failures + fixes (read before your first merge)
    └── ledger-template.md       # the boolean-gate ledger schema (the coordinator's external brain)
```

# Known gotchas

Captured in full in `references/gotchas.md`. The ones that bite first:

| Gotcha | Fix |
|---|---|
| A worker reports "merged" but the PR is `UNSTABLE` forever (a hung review-bot autofix check) | Once real gates are green + review concluded, merge with `--admin`; then **verify** `state=MERGED`. |
| A fix shows `MERGED` but isn't on your integration base — a builder self-opened a PR against `main` | Builders never open PRs; integrators assert `baseRefName==BASE` before merging; verify the fix is on base. |
| A subprocess-heavy adversarial test times out on CI but passes on a sibling run | It's a flake, not a finding — widen that test's timeout (don't re-run and hope). |
| Migration-number collisions across parallel slices | Pre-assign lanes; the later one renumbers to next-free-above-highest-on-base, or the runner skips it. |
| Green unit tests ≠ working product | The anti-inflation E2E gate (public entry points, real persisted state, negative controls with teeth). |

# Compatibility

Requires the **Orca** multi-agent runtime (running, orchestration experimental feature enabled) and the
companion `orchestration` skill. Worker CLIs `codex`/`claude` on PATH; `git` + `gh`; `python3`; bash/zsh.
Optional: `gitleaks` (scoped secret scans) and a PR review bot (e.g. Cursor BugBot). The coordination layer
is Orca-specific; on another harness only the strategy half (`references/`) carries over.

# Pairs with

- [`clean-sweep`](../clean-sweep/) — the sibling for an *existing* repo: find and close every issue with the
  same coordinator/build-blind-review/PR-per-unit pipeline. `spec-to-ship` builds greenfield; `clean-sweep`
  fixes brownfield.

# Credits

Distilled from a real end-to-end autonomous multi-agent product build. MIT licensed.
