# Review-Matrix — PR #11 (fleet-ops wave 2)

| Field | Value |
|-------|-------|
| reviewed_sha | `9e5c8eac7b587e9bc95c23d0a3c64a9aaeeacd28` |
| Fixed point | `09ff119` (main @ PR #10 merge) … `9e5c8ea` (PR #11 merge) |
| Scope | `quorum`, `spec-decompose`, `ephemeral-fleet`, `fleet-memory` + qa/ios-qa/model-jury/guard/review wiring |
| Reviewer | Cursor cloud agent (direct dual-axis; Orca runtime not available in this environment) |
| Date | 2026-07-12 |
| Prior reviews | Codex round 3 MERGE-READY YES (`docs/reviews/codex-pr4.md`); Greptile confidence 3/5 with open inline comments |

**Verdict: MERGE-READY NO for residual contract gaps** — PR already landed on `main`; treat findings as a follow-up fix wave before consumers trust completion/ledger contracts.

Findings use the AGENTS.md schema. Axes are not reranked across sections.

---

## Standards

### RM-001 — P1 — Ledger templates do not match completion contracts
- **axis:** standards
- **file:** `skills/{quorum,spec-decompose,ephemeral-fleet,fleet-memory}/references/ledger-template.md`
- **line:** 1
- **summary:** All four templates are identical copies of the generic orchestration ledger. Each SKILL.md Scripts section claims the template encodes skill-specific schema (quorum ballot/reduction tables; slice↔task-id table; lane table; injected-keys / stats lines), and each Completion contract makes those rows the definition of DONE. An agent bootstrapping from the template produces an unauditable run — directly contradicting quorum's "a vote you can't audit from the ledger didn't happen."
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Extend each template with the sections named in that skill's completion contract (do not leave "extends" as prose-only).

### RM-002 — P2 — READMEs reference missing `assets/banner.jpg`
- **axis:** standards
- **file:** `skills/{quorum,spec-decompose,ephemeral-fleet,fleet-memory}/README.md`
- **line:** 1
- **summary:** Each README embeds `<img src="assets/banner.jpg">` but only `banner-prompt.txt` is committed (OPENROUTER pending by design). Broken hero images on every new skill README; same gap remains on wave-1 fleet-ops skills.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Generate banners when `$OPENROUTER_API_KEY` is available, or stop claiming the image exists until then.

### RM-003 — P2 — `docs/fleet-memory/` store path not seeded
- **axis:** standards
- **file:** `skills/fleet-memory/SKILL.md`
- **line:** 32
- **summary:** Compatibility and store sections put learnings at `docs/fleet-memory/learnings.jsonl` and `specialist-stats.jsonl`, but the directory is absent from the repo. First inject has no checked-in convention (gitignore? empty JSONL? README?). Coordinators will invent divergent layouts.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Seed `docs/fleet-memory/` with empty JSONL files (or a short README stating create-on-first-write) and document whether the store is committed.

---

## Spec

### RM-004 — P1 — Fleet-memory injection selection non-deterministic above cap
- **axis:** spec
- **file:** `skills/fleet-memory/SKILL.md`
- **line:** 68
- **summary:** Spec: "CAP at 5 per task". When >5 active lines match, no sort/tiebreak is stated. Two runs of the same fleet can inject different subsets; the ledger's injected-keys line cannot explain *why* those five won. (Also flagged Greptile P1 on PR #11 — still open on `main`.)
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** State a total order, e.g. confidence desc → date desc → key asc; take top 5; record the rule in the ledger.

### RM-005 — P1 — NEVER_GATE / specialist names do not map to review axes
- **axis:** spec
- **file:** `skills/fleet-memory/SKILL.md`
- **line:** 91
- **summary:** NEVER_GATE lists `security/authz` and `data-migration`. `review-matrix` axes are Standards / Spec / security-lite / test-adequacy. `review-prod-fleet` axes are SQL/data, AuthZ, LLM/tool trust, Conditional side effects — none named `data-migration` or `security/authz`. Stats example uses `"specialist": "authz"`. Coordinators cannot decide which axis id to write or which NEVER_GATE key protects which task without inventing a mapping the skills never publish.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Publish a specialist↔axis id table shared by fleet-memory, review-matrix, and review-prod-fleet; NEVER_GATE must use those exact ids.

### RM-006 — P2 — `confidence` scale undocumented in store schema
- **axis:** spec
- **file:** `skills/fleet-memory/SKILL.md`
- **line:** 36
- **summary:** Example shows `"confidence": 8`; Rules say confidence `<5` does not inject. Range (integer 1–10?) is never stated in the JSONL schema. (Greptile P2 — open.)
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Document `confidence` as integer 1–10 in the store block; threshold `<5` holds pending corroboration.

### RM-007 — P2 — Quorum poll deadline `T` has no default
- **axis:** spec
- **file:** `skills/quorum/SKILL.md`
- **line:** 53
- **summary:** COLLECT requires nudge at T/2 and close at T, but T is never sized. Late-vote "noted, not counted" has no concrete boundary. (Greptile P2 — open.)
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Declare a default (e.g. `T = max(20m, N_voters × 10m)`, cap 2h) and require the chosen T in the ledger.

### RM-008 — P2 — model-jury Process still forks from quorum protocol home
- **axis:** spec
- **file:** `skills/model-jury/SKILL.md`
- **line:** 46
- **summary:** "Protocol home" says run through quorum Mode 2 (ballot/reduction/routing; jurors never vote their own candidate; human always picks winner). Process steps 4–5 still describe a coordinator comparison table + `gate-create` pick A/B/hybrid without mandating quorum VOTE, QID, or denominator honesty. Two playbooks can diverge mid-jury.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Replace steps 4–5 with an explicit call into quorum VOTE (voters ≠ authors) + human gate; keep hybrid rules as the human's options.

### RM-009 — P2 — Quorum README oversimplifies routing vs JURY invariant
- **axis:** spec
- **file:** `skills/quorum/README.md`
- **line:** 16
- **summary:** README: "Unanimous acts; splits become taste gates." SKILL Mode 1 ROUTE carves an EXCEPTION: JURY winner picks always go to the human. A reader who only loads the README will auto-act a unanimous jury — the exact failure Mode 2 forbids.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** One sentence: unanimous VOTE may act; JURY winner pick is always human-gated.

---

## Security-lite

### RM-010 — P2 — Surface-matching rule for learnings is under-specified (injection scope)
- **axis:** security
- **file:** `skills/fleet-memory/SKILL.md`
- **line:** 68
- **summary:** Selection includes lines that "touch its surface (worktrees, merges, migrations…)". Without a defined matcher, coordinators may over-inject (wrong fleet's operational gotchas into unrelated tasks) or under-inject. Not a secret leak by itself, but weakens the "learnings state FACTS about this repo" boundary when keys are loosely matched.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Prefer exact `fleet` match first; optional tag allowlist on the task; forbid cross-fleet inject unless tag intersection is non-empty.

No hardcoded secrets in the diff. `ephemeral-fleet` + `guard-policy` correctly keep PROFILE=danger off the integrator machine and forbid live credential injection into sandboxes. `fleet-memory` correctly bans secrets from the committed JSONL store.

---

## Test-adequacy

### RM-011 — P2 — No behavioral tests for new completion contracts
- **axis:** test-adequacy
- **file:** `skills/quorum/SKILL.md` (representative)
- **line:** 88
- **summary:** Wave 2 adds protocol contracts (denominator honesty, harvest-before-destroy, foreign-task precondition, stats gating) with no fixture or validator assertion that ledger templates contain required sections, or that NEVER_GATE ids match review axis ids. `validate-skills.py` only checks frontmatter. Reverting a completion-contract paragraph would not fail CI.
- **reviewed_sha:** `9e5c8ea`
- **report_path:** `docs/reviews/review-matrix-9e5c8ea.md`
- **fix:** Add a cheap static check: ledger-template headings ⊇ completion-contract required sections; specialist id set shared across the three skills.

---

## Open Greptile residuals (still on `main` after merge)

| Source | Sev | Item | Status in this review |
|--------|-----|------|------------------------|
| PR #11 Greptile | P1 | Learning selection order above cap | Confirmed → RM-004 |
| PR #11 Greptile | P2 | confidence scale | Confirmed → RM-006 |
| PR #11 Greptile | P2 | Vote deadline T | Confirmed → RM-007 |
| PR #11 Greptile summary | — | Generic ledger templates | Confirmed → RM-001 |
| PR #10 Greptile | P2 | Missing banners (wave 1) | Same class → RM-002 |
| PR #10 Greptile | P2 | `pm.py` bare argv IndexError | Still present in `scripts/orca-coord/pm.py` L16 (`sys.argv[1]` ungarded) |
| PR #10 Greptile | P2 | `parser.error` exit 2 vs invariant contract | Still present (argparse default) |

---

## What looks solid (no finding)

- Catalog/MANIFEST/AGENTS/README counts consistent at 46 skills; `sync-orca-coord` 41×4 clean; `validate-skills.py` green.
- Codex PR4 P1/P2 fixes verified present: QID spanning fan-outs; foreign-task precondition; lane harvest to work branches not BASE; fleet-memory gating owned by review coordinators; JURY exception in VOTE ROUTE; guard-over-sandbox danger precedence.
- qa-fleet / ios-qa-fleet mechanics are concrete and actionable (page ownership, snapshot invalidation, 2-consecutive re-verify; workspace-scoped emulator lifecycle).

---

## Summary

| Axis | Findings | Worst |
|------|----------|-------|
| Standards | 3 | P1 — ledger templates vs completion contracts (RM-001) |
| Spec | 6 | P1 — inject tiebreak (RM-004); specialist↔axis map (RM-005) |
| Security-lite | 1 | P2 — surface-match scope (RM-010) |
| Test-adequacy | 1 | P2 — no contract tests (RM-011) |

**Standards:** 3 findings (worst: P1 ledger templates)
**Spec:** 6 findings (worst: P1 selection order + axis id map)
**Security-lite:** 1 finding (worst: P2)
**Test-adequacy:** 1 finding (worst: P2)

**Gate:** human decide follow-up fix tasks; do not treat Codex MERGE-READY as fresh evidence that Greptile residuals and RM-001/004/005 are closed — they are not on `9e5c8ea`.
