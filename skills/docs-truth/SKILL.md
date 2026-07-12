---
name: docs-truth
description: >-
  Autonomous mission: make the docs true. Verify every claim in the documentation against
  the actual codebase (does that API/flag/path/example still exist and behave as
  described?), fix or regenerate the false ones per Diataxis, PR-per-doc-area, and loop
  until zero claims are untraceable to the tree. Use when "the docs are out of date",
  docs truth, verify the documentation, doc rot, fix the README claims, or an unattended
  documentation-accuracy run. Truth-first, not prose-polishing.
license: MIT
compatibility: >-
  HARD dependency: Orca runtime + orchestration skill (Orca CLI); git + gh; the docs and
  the code in one repo. Worker playbooks: addyosmani/agent-skills
  (documentation-and-adrs, source-driven-development) or gstack (document-generate) — one
  router per worker (verify names against the installed pack). In-pack: merge-train,
  run-supervision, gate-steward, run-supervision.
---

# Docs-Truth — every documented claim traces to the tree, or it's gone

You are the **COORDINATOR** of an autonomous mission. The end state is EVIDENCE: every
factual claim in the documented surface is TRACEABLE — the API/flag/command/path/example
it describes exists and behaves as written, verified against the code, not the model's
memory of how it probably works. Untraceable claims are fixed, regenerated, or removed —
never left to mislead.

## ⚠️ HARD BASE: Orca `orchestration`

**This skill is built on Orca orchestration — we have Orca; we do not replace it.**

| Layer | Owns | Source |
|-------|------|--------|
| **Runtime** | tasks, dispatch, `worker_done`, gates, DAG, worktrees | Orca |
| **Grammar** | CLI + lifecycle | **`orchestration` skill from Orca CLI** (not this repo) |
| **This mission** | claim-extract→verify→fix loop, evidence | this repo |
| **Worker playbooks** | docs/ADRs, source-grounding | Addy documentation-and-adrs OR gstack document-generate |

**Preflight:** `orca status --json` · orchestration on · `preflight.py --base {{BASE}}`
green · docs live in-repo (or a fetchable path) · clean baseline.

## Mission parameters

- `{{BASE}}` · `{{MAX_WORKERS}}` · `{{DOC_SURFACE}}` (README, docs/, API reference,
  runnable examples, inline docstrings — confirm scope once) · `{{EXAMPLES_RUNNABLE}}`
  (can code examples be executed to verify? enables the strongest check).

## Phase graph

```
ORIENT → EXTRACT claims (per doc area) → VERIFY each against the tree (ro)
  → FIX/REGENERATE/REMOVE waves (PR-per-area) → build-blind REVIEW → merge-train
  → RE-EXTRACT (loop until zero untraceable) → REFLECT
```

## Phase 1 — EXTRACT claims (make the surface finite and checkable)

Per doc area, a `PROFILE=ro` worker pulls out the FALSIFIABLE claims — "call `foo(x, opts)`
returns Y", "the `--strict` flag does Z", "config lives at `path/to/thing`", "this example
prints …". Prose opinions and philosophy are out of scope; verifiable facts are the
mission. Ledger (`docs/docs-truth-progress.md`): `| doc | claim | VERDICT (true/false/
stale/unverifiable) | evidence (file:symbol or run) | ACTION | PR | MERGED |`.

## Phase 2 — VERIFY each claim against the code (source-driven, not memory)

`PROFILE=ro` verifier workers, playbook = source-driven grounding:

- Every claim is checked against the ACTUAL tree: does the symbol exist at the stated
  path? does the signature match? Where `{{EXAMPLES_RUNNABLE}}`, RUN the example and diff
  its output against the documented output — a runnable example that doesn't produce the
  documented result is FALSE, full stop.
- Verdict per claim: true (traceable) · false (contradicts the code) · stale (was true,
  the code moved) · unverifiable (no way to check — flag for a human, don't guess).
- Anti-hallucination rule: the verifier cites `file:symbol` or a pasted command+output as
  evidence. "Looks right" is not a verdict.

## Phase 3 — FIX / REGENERATE / REMOVE waves (PR-per-doc-area)

`PROFILE=rw` worker per doc area (same-file docs = merge chain):

- **false/stale** → correct the claim to match the code, or REGENERATE the section per
  Diataxis (tutorial/how-to/reference/explanation — reference docs get regenerated from
  the code where a generator exists). A claim describing a REMOVED feature → remove it
  (deleting a lie is a fix).
- **The code is right, the doc is wrong** → fix the doc. **The doc describes intended
  behavior the code doesn't do** → that's a BUG, not a doc fix: PARK as needs-human or
  hand to `clean-sweep` — never "fix" the doc by documenting the broken behavior as
  intended.
- Add a traceability anchor where cheap (a doc-test, a `<!-- verified: file:symbol -->`
  marker) so the next run re-checks fast.
- Build-blind REVIEW (does the new doc match the cited code?), `merge_ready` →
  **merge-train**.

## Phase 4 — RE-EXTRACT + loop

Re-extract claims after each wave (regenerated docs introduce new claims; merged code
changes stale others). The mission converges when a fresh extraction over the surface
finds zero false/stale claims and every unverifiable one is parked with a human note.

## Two named terminal outcomes

- **TRUE** — every falsifiable claim on the surface is verified true or fixed to be true;
  zero false/stale claims remain. A completed mission.
- **TRUE-WITH-UNVERIFIABLE** (degraded, not TRUE) — zero false/stale claims, but ≥1 claim is
  UNVERIFIABLE (no way to check without a human / private system) and parked with a note.
  The ledger names each. Legitimate stop, never reported as TRUE.

## Completion contract (evidence — the outcome must be named)

- Ledger outcome line = `TRUE` or `TRUE-WITH-UNVERIFIABLE` with the list.
- Every falsifiable claim on the surface has a recorded verdict with `file:symbol`-or-run
  evidence.
- Every false/stale claim: fixed/regenerated/removed in a merged PR (ancestry-verified),
  spot-audited on a sample by a fresh worker re-verifying against the tree.
- Every runnable example (when `{{EXAMPLES_RUNNABLE}}`): executed, output matches the doc,
  the run pasted.
- Doc-described-but-unimplemented behavior: handed to `clean-sweep` or parked, never
  papered over.
- Final re-extraction pasted showing zero untraceable claims (or the parked list).
- Promotion to default is out of scope.

## RESUME

`run-supervision` RESUME scoped to this ledger; a doc fix claimed merged is re-verified by
ancestry, and claim verdicts are re-checkable against the tree — never trusted from
memory. Re-extract to catch claims that went stale while the coordinator was down.

## Anti-patterns

- "Improving" prose without verifying the facts (polish over a false claim = a prettier
  lie).
- Documenting broken behavior as intended (locks in the bug; route it to clean-sweep).
- Verifying from the model's memory of the API instead of the tree (the exact rot that
  created the drift).
- Regenerating reference docs that then contradict hand-written how-tos (re-extract
  catches this; reconcile, don't leave both).

## Handoff contract

Emits the claims ledger (verdicts, evidence, actions), doc-surfaced bugs to
`clean-sweep`, and REFLECT learnings to `fleet-memory`. Schedulable via `standing-fleet`
(precheck: docs or public API changed since last run).

## Variants (absorbed skills)

- **mode=generate** (was `docs-fleet`): generate/refresh docs per Diataxis after code lands (Phase 3 without the verify-first phases). The default `mode=verify` checks existing claims against the tree.

## Related

`mode=generate` (this skill's generation variant — the default `mode=verify` is
verification-first), `clean-sweep` (doc-surfaced bugs), `merge-train`, `run-supervision`, `gate-steward`, 
`run-supervision`, `fleet-memory`.

## Scripts & assets

- `scripts/spawn_worker.sh` — calls Orca (fail-closed dispatch; PROFILE=ro|rw|danger) · `preflight.py` — git/gh + BASE invariants (no Orca) · `pm.py` — inbox/check JSON parser (no Orca)
- `references/ledger-template.md` — the claim/verdict ledger schema

Load the Orca **`orchestration`** skill for command grammar. This skill supplies the mission; Orca supplies the machine.
