# Review-Matrix — PR #11 (fleet-ops wave 2)

| Field | Value |
|-------|-------|
| reviewed_sha | `9e5c8eac7b587e9bc95c23d0a3c64a9aaeeacd28` (findings fixed on follow-up branch) |
| Fixed point | `09ff119` … `9e5c8ea` (PR #11 merge) |
| Scope | `quorum`, `spec-decompose`, `ephemeral-fleet`, `fleet-memory` + qa/ios-qa/model-jury/guard/review wiring |
| Reviewer | Cursor cloud agent (direct dual-axis; Orca runtime not available in this environment) |
| Date | 2026-07-12 |
| Remediation | All RM-001…RM-011 + PR #10 Greptile residuals addressed on `cursor/review-pr11-fleet-ops-09b6` |

**Original verdict:** MERGE-READY NO (residuals on `9e5c8ea`).
**After remediation:** findings closed — see disposition table.

---

## Disposition

| ID | Sev | Axis | Status | Fix |
|----|-----|------|--------|-----|
| RM-001 | P1 | standards | **FIXED** | Skill-specific ledger templates for quorum / spec-decompose / ephemeral-fleet / fleet-memory |
| RM-002 | P2 | standards | **FIXED** | Broken `banner.jpg` embeds → pending-OPENROUTER comments (wave 1+2 fleet-ops) |
| RM-003 | P2 | standards | **FIXED** | Seeded `docs/fleet-memory/{learnings,specialist-stats}.jsonl` + README |
| RM-004 | P1 | spec | **FIXED** | Inject tiebreak: confidence desc → date desc → key asc; cap 5 |
| RM-005 | P1 | spec | **FIXED** | Canonical specialist id table; NEVER_GATE = `security-lite`, `authz`, `sql` |
| RM-006 | P2 | spec | **FIXED** | `confidence` documented as integer 1–10 |
| RM-007 | P2 | spec | **FIXED** | Default `T = max(20m, N_voters × 10m)`, cap 2h |
| RM-008 | P2 | spec | **FIXED** | model-jury Process steps 4–5 route through quorum VOTE + human gate |
| RM-009 | P2 | spec | **FIXED** | Quorum README: JURY winner always human-gated |
| RM-010 | P2 | security | **FIXED** | Fleet match + tag intersection only (no fuzzy surface match) |
| RM-011 | P2 | test-adequacy | **FIXED** | `tests/test_ledger_contracts.py` |
| PR10 pm.py | P2 | — | **FIXED** | Argv guard → usage exit 1 |
| PR10 preflight | P2 | — | **FIXED** | Missing `--base` → exit 1 (usage), not argparse/SystemExit(2) |

---

## Summary (post-fix)

Standards / Spec / Security-lite / Test-adequacy: **0 open findings** from this review pass.

**Gate:** human merge of remediation PR; regenerate banners when `$OPENROUTER_API_KEY` is available (prompts committed; images intentionally deferred).
