---
name: dep-fresh
description: >-
  Autonomous mission: bring every dependency current, safely. Upgrade in
  expand/migrate/contract batches (one dep or one coherent group per PR), run framework
  migrations behind the same discipline, keep CI green throughout, and loop until every
  outdated major is either upgraded or parked with a written reason. Use when "update the
  dependencies", dep fresh, upgrade everything, framework migration, "get off the old
  major", or an unattended dependency-currency run. Reachability-triaged, not blind
  bumping.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; the project's
  package manager + a green CI baseline. Worker playbooks: addyosmani/agent-skills
  (deprecation-and-migration, security-and-hardening supply-chain, code-review dep
  discipline) — one router per worker (verify names against the installed pack). In-pack:
  merge-train, run-supervision, gate-steward, run-supervision, quorum.
---

# Dep-Fresh — every major current or parked with a reason, CI green the whole way

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE: every
dependency is on a current supported version, OR pinned-and-parked with a written reason
a human approved (a breaking upstream, a dropped platform, a transitive conflict). CI is
green at every merge — a dep mission that reds the pipeline is a regression, not progress.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | inventory→batch→upgrade→verify loop, evidence | this repo |
| **Worker playbooks** | deprecation/migration, supply-chain | Addy deprecation-and-migration (one router per worker) |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · CI green at baseline (you can't attribute a red to your upgrade otherwise) ·
lockfile committed · clean baseline.

## Mission parameters

- `{{BASE}}` · `{{MAX_WORKERS}}` · `{{ECOSYSTEM}}` (npm/pnpm/pip/cargo/…) ·
  `{{RUN_LEVEL}}` (patch+minor only / include-majors / include-framework-migrations) ·
  `{{CI_CMD}}` (the gate every upgrade must keep green) · `{{SUPPORT_POLICY}}` (optional:
  the project's supported-version rule — e.g. "stay on active-LTS" — else derived per Phase 1).

## Phase graph

```
ORIENT → INVENTORY (outdated + advisories + reachability) → order by risk
  → UPGRADE waves (one dep/group per PR: bump → fix → CI green) → build-blind REVIEW
  → merge-train → MIGRATION lanes (expand/migrate/contract) → RE-INVENTORY → loop → REFLECT
```

## Phase 1 — INVENTORY (what's stale, how risky, is it even reachable)

- List outdated (`npm outdated` / `pip list --outdated` / equiv) + security advisories
  (`npm audit` / `pip-audit`). For each, read the CHANGELOG, not just the version delta
  (the code-review dep discipline) — is the major a real breaking change or a version-
  policy bump?
- **"Current supported" authority (record it — registry-latest is NOT the truth):** the
  target is the version the PROJECT supports, decided by, in order: an explicit project
  constraint (engines/peerDeps/`{{SUPPORT_POLICY}}`), then the dependency's own published
  support/EOL policy (LTS line, security-maintenance window), then registry-latest only
  when neither exists. A dep on a still-supported older major is CURRENT, not outdated —
  the ledger records which authority set each target.
- **Reachability triage** (Addy supply-chain): a vuln/major in a dev-only or unreachable
  transitive dep is lower priority than a runtime-critical one. Never `npm audit fix
  --force` blindly — that's a mass unreviewed bump.
- Ledger (`docs/dep-fresh-progress.md`): `| dep | cur→target | kind (patch/minor/major/
  migration) | reachability | UPGRADED | PR | CI-GREEN | MERGED | notes |`.
- Order: security-critical-reachable → patch/minor (low risk, batch coherent groups) →
  majors (one per PR) → framework migrations (their own lane).

## Phase 2 — UPGRADE waves (one dep or one coherent group per PR)

`PROFILE=rw` worker per upgrade (shared-lockfile PRs form a merge chain — never parallel-
bump the lockfile):

- One dep, or one coherent group (a framework + its plugins that MUST move together), per
  PR — the "one-dep-per-change, let tests decide" discipline. Bump → fix the call sites
  the new version breaks → **`{{CI_CMD}}` GREEN is the gate** (a red CI is a blocked PR,
  never a merged one).
- Keep the lockfile honest (regenerate, don't hand-edit). Verify signatures/provenance
  for anything that changed registry or maintainer (supply-chain hygiene). Block install
  scripts of a newly-added transitive dep before first run where the ecosystem allows.
- Behavior-changing majors: the upgrade PR carries a test proving the new behavior is
  handled, not just "it compiles".
- Build-blind REVIEW (dep discipline axis + correctness), `merge_ready` → **merge-train**.

## Phase 3 — MIGRATION lanes (only when `{{RUN_LEVEL}}` includes them)

Framework/API migrations and any DB schema change use **expand/migrate/contract**, never
rename-in-place:

- expand (add the new, keep the old) → migrate call sites in batches, each a PR keeping CI
  green → contract (remove the old) in a SEPARATE later PR. Every DB migration has a
  tested `down`. Destructive contract steps (dropping a column, deleting a compat shim
  users may depend on — Hyrum's Law) are **one-way → human gate** via gate-steward, never
  auto-applied.
- Strangler/adapter patterns for big API moves; zombie-code sweep after.

## Phase 4 — RE-INVENTORY + loop

Re-run Phase 1 after each wave (upgrades unlock or block others; a major may bump a
transitive that now needs its own PR). The mission converges when a fresh inventory shows
every dep on a current supported version OR parked with a reason. New advisories mid-run
→ new rows → next wave.

## Two named terminal outcomes

- **CURRENT** — every dep on a current supported version, zero reachable unaddressed
  advisories. A completed mission.
- **CURRENT-WITH-PINNED** (degraded, not CURRENT) — all upgradable deps current, but ≥1 is
  pinned-and-parked (breaking upstream / dropped platform / unresolved conflict) with a
  human reference. The ledger names each pin. Legitimate stop, never reported as CURRENT.

## Completion contract (evidence — the outcome must be named)

- Ledger outcome line = `CURRENT` or `CURRENT-WITH-PINNED` with the pin list.
- Every outdated dep at Phase 1 reaches a terminal state: upgraded+merged with CI green
  (the green run referenced), or PARKED-pinned with a written reason + human reference
  (breaking upstream / dropped platform / unresolved conflict).
- Every merge kept CI green (no red pipeline landed — check the merge commits' checks).
- Migration lanes: expand and contract are SEPARATE merged PRs; every DB migration has a
  tested `down`; destructive contracts have their human-gate reference.
- `npm audit` / advisory scan re-run at the end: zero reachable unaddressed advisories, or
  each remaining one parked with reachability rationale.
- Final inventory pasted in the ledger showing the current/parked state.
- Promotion to default is out of scope.

## RESUME

`run-supervision` RESUME scoped to this ledger; an upgrade claimed merged is re-verified by
ancestry AND by re-reading the lockfile on `{{BASE}}` (the version actually landed), never
from worker memory. In-flight migration lanes resume at their expand/migrate/contract
stage.

## Anti-patterns

- `npm audit fix --force` / mass-bump-everything (a hundred unreviewed changes, one red).
- Rename-in-place migrations (breaks dual-running deploys — expand/contract always).
- Landing a red CI "to fix in the next PR" (the mission's whole point is green-throughout).
- Bumping a major without reading its changelog (version delta ≠ breaking-change scope).
- Dropping a compat shim without a human gate (something depends on it — Hyrum's Law).

## Handoff contract

Emits the dependency ledger (versions, CI-green references, migration stages, parked
reasons), findings in the AGENTS.md schema for advisory-driven upgrades, and REFLECT
learnings to `fleet-memory`. Schedulable via `standing-fleet` (weekly: precheck = any
new outdated major or advisory).

## Related

`red-team-harden` (supply-chain advisories overlap — dep-fresh does the upgrades, red-team
does the exploit proof), `clean-sweep`, `merge-train`, `run-supervision`, `gate-steward`, 
`run-supervision`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the dependency/migration-lane ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
