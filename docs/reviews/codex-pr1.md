# Codex re-review — PR1 (fleet substrate)

Reviewer: codex exec, gpt-5.6-sol, read-only sandbox. Date: 2026-07-12.
Scope: git diff main...HEAD on branch ravidsrk/fleet-substrate (initial 4-commit state).
Disposition: all P1s and P2s below were fixed in the follow-up commit on this branch
(see docs/remediation-log.md); tests extended to cover each. P2-3 CI wiring disposition:
behavioral suite runs via scripts/test-orca-coord.sh; validate-skills.py stays fast and
runs the sync --check only.

## VERDICT

**Merge-ready: NO.**

The remediation is meaningful, but three P1 safety gaps remain: the launcher still fails open on some Orca error envelopes, malformed dependency metadata can bypass the DAG, and vendored-helper validation does not detect deleted copies.

Validation observations:

- `scripts/sync-orca-coord.py --check` reports all 96 currently present copies synchronized.
- `scripts/validate-skills.py` passes all 37 skills.
- Shell syntax checks pass.
- Behavioral tests could not run in this read-only review sandbox because no writable temporary directory was available; this is environmental, not itself a PR defect.

## PER-FINDING TABLE

| Finding | Status | Evidence |
|---|---|---|
| **B1** | **PARTIAL** | `set -euo pipefail` and DAG-state checks are real at `scripts/orca-coord/spawn_worker.sh:34,87-137`, but malformed `deps` becomes dependency-free at `:103-109`, several JSON errors are discarded at `:127,159,177`, and the stale repeated-Enter sequence remains at `:175-189`. |
| **D1** | **PARTIAL** | Named aliases are correctly canonicalized at `scripts/orca-coord/preflight.py:67-88,159-173` and tested at `tests/test_preflight.py:91-106`; however, a tag or raw SHA resolving to the default tip passes as a “BASE branch” because existence accepts any rev and same-tip is only a warning at `:175-201`. |
| **D2** | **VERIFIED** | Both workflows now pin the selected Git base: `skills/design-it-thrice/SKILL.md:74-77` and `skills/model-jury/SKILL.md:43`. |
| **D3** | **VERIFIED** | `ro`, `rw`, and opt-in `danger` profiles use valid Codex/Claude flags at `scripts/orca-coord/spawn_worker.sh:60-84`; danger requires `ORCA_COORD_ALLOW_DANGER=1`, and read-only fleets document `PROFILE=ro`, e.g. `skills/benchmark-fleet/SKILL.md:41-43`. |
| **D4** | **VERIFIED** | Both peers require `--force-with-lease`, e.g. `skills/spec-to-ship/assets/integrator_preamble.txt:9` and `merge_preamble.txt:12,15`; `--admin` requires a recorded human grant at `skills/spec-to-ship/SKILL.md:153-158`. |
| **D5** | **VERIFIED** | `--mode readonly` omits `gh` and all BASE/PR invariants at `scripts/orca-coord/preflight.py:122-146`; applicable fleet instructions select it, e.g. benchmark `SKILL.md:41-43`, office-hours `SKILL.md:44-45`, and retro `SKILL.md:42-43`. |
| **B5** | **VERIFIED** | Durable `reply --id <CURRENT>` is now primary, with terminal injection limited to an expired-ask fallback at `skills/spec-to-ship/SKILL.md:162-165` and `references/gotchas.md:35-49`. |
| **A4** | **NOT-FIXED** | Vendored comments now point to root-relative `scripts/orca-coord/README.md`, e.g. `skills/benchmark-fleet/scripts/spawn_worker.sh:28`; that path still does not exist inside a standalone installed skill, so the phantom reference was replaced rather than eliminated. |
| **E2** | **PARTIAL** | Current copies are generated and validator-checked at `scripts/sync-orca-coord.py:28-76` and `scripts/validate-skills.py:127-132`, but globbing only existing files means deleted helpers are invisible; tests also omit `pm.py` and are not wired into validation. |
| **E3** | **PARTIAL** | Missing fields and malformed-line recovery are improved at `scripts/orca-coord/pm.py:23-55`, but line-level heartbeat filtering can discard valid messages at `:16`, same-line recovery remains brittle at `:31-37`, and no parser tests exist. |

## NEW DEFECTS

### P1 — Malformed dependency data fails open

`scripts/orca-coord/spawn_worker.sh:103-109` catches invalid string-valued `deps` and replaces it with `[]`. With `--mark-ready`, corrupt dependency metadata therefore yields `unmet=0`, allowing the script to mark and dispatch a task whose dependencies are unknown.

The tests cover only valid dependency lists at `tests/test_spawn_worker.sh:59-70`.

### P1 — Orca error envelopes are silently accepted

The launcher validates JSON errors from terminal creation and dispatch, but not from:

- `task-update`: `scripts/orca-coord/spawn_worker.sh:127`
- `terminal wait`: `:159`
- Initial `terminal send`: `:177`
- Retry sends: `:188`

If Orca returns exit 0 with `{"error":"…"}`, these steps continue. A failed readiness update can be followed by dispatch, while a failed prompt submission can still report success if dispatch heartbeat state exists.

The fake Orca deliberately models exit-0 error envelopes for create/dispatch at `tests/test_spawn_worker.sh:23-27`, but never tests them for update, wait, or send.

### P1 — Sync validation cannot detect deleted helpers

`scripts/sync-orca-coord.py:41-42,53-56` derives the expected set from files currently found by `glob`. Deleting one vendored helper merely reduces `total`; `--check` still succeeds. Deleting an entire helper family could therefore pass the validator.

The checker needs an explicit expected skill set or manifest and must require all three helpers for each participating skill.

### P2 — Executable-bit drift is ignored

`scripts/sync-orca-coord.py:57-65` compares content only and skips `chmod` when content matches. A synchronized `spawn_worker.sh` with its executable bit removed passes `--check`, and a normal sync does not repair it.

### P2 — Parser can discard valid messages

`scripts/orca-coord/pm.py:16` deletes any whole line containing `"_heartbeat"`. A single-line object containing both heartbeat metadata and `result.messages` loses its messages. Recovery at `:31-37` also skips valid JSON appearing later on the same noisy line.

### P2 — Parser remediation is untested

`scripts/test-orca-coord.sh:7-12` runs preflight and launcher tests only. There are no behavioral tests for malformed mailbox segments, missing fields, heartbeat envelopes, or recovery after noise.

### P2 — Invalid agent names silently select Claude

Usage promises `agent: claude|codex`, but `scripts/orca-coord/spawn_worker.sh:85` maps every value other than literal `codex` to Claude. A typo should be rejected with policy/usage exit 2.

### P2 — Preflight accepts non-branch revisions

`scripts/orca-coord/preflight.py:51-56,91-96` treats any resolvable revision as an existing BASE. Tags and raw SHAs can pass the branch guard; same-tip identity only generates a warning at `:194-201`.

## P1 LIST

1. Parse and reject every Orca JSON error envelope for task update, terminal wait, and terminal send.
2. Reject malformed or non-list dependency metadata instead of treating it as no dependencies.
3. Make sync validation assert the complete expected helper inventory, including deleted/missing copies.
4. Remove or narrowly justify the repeated unconditional Enter retries before calling B1 fully remediated.

## P2 LIST

1. Validate and restore executable modes during synchronization.
2. Parse heartbeat envelopes structurally rather than filtering lines by substring.
3. Add `pm.py` behavioral tests and wire the substrate suite into CI/validation.
4. Reject unknown agents and surplus launcher arguments.
5. Require BASE to resolve to an actual local/remote branch, not a tag or raw SHA.
6. Replace the standalone-invalid generated README reference with a packaged/local reference.

## Re-verification (same day, after fix commits c6520dd / dda3051 / b61642a)

Focused codex exec re-run over the fix delta. First pass returned P1-2 PARTIAL
(falsey malformed deps — '', 0 — still coerced to 'no deps' by the `or []` shortcut);
fixed in b61642a with S13b regression coverage. All other items FIXED, no new P1
regressions. Final verdict: MERGE-READY: YES.
