# Verification layer — proving the build actually works (the part that catches real bugs)

A green unit suite proves nothing about the *system*. In a real run the decisive bugs — cross-tenant
data leaks, spend bypasses, path traversal, hollow/non-durable persistence — were all found by three
verification mechanisms that sit ABOVE the per-task tests: the anti-inflation e2e gate, adversarial
refuse-surface suites, and drift ratchets. Build these as first-class tasks, not afterthoughts.

## 1. The anti-inflation e2e gate (with teeth)

**Claim being tested:** "the product does the thing end-to-end," not "each unit passes."

- Drive the golden path ONLY through the **true public entry points** — the REST API, the MCP/tool
  surface, and the **real CLI binary over loopback** with a real principal key. No importing internal
  functions, no test-only shortcuts. If a caller in production couldn't do it, the test can't either.
- Assert **REAL persisted state**, not exit codes: query Postgres for the concrete job/approval rows,
  read the memory store for the entity you created, read the projected `.agents/`-style file off disk.
  "Exit 0" is inflation; "row exists in the DB with the expected status" is proof.
- **Negative controls must have teeth.** Each negative control breaks a required precondition (drop the
  auth key, corrupt the input, revoke the scope) and asserts the path goes **RED**, then **restores** and
  asserts GREEN again. A negative control that can't go red is decoration. Verify each one reddens by
  actually reverting the guard once (red-by-revert) — see §4.

**The gate surfaces deferred/hollow infrastructure — build it, don't defer past the gate.** In the real
run, the e2e gate exposed that "jobs are persisted" was a lie: the JobStore was file-backed only, no
Postgres table. The right move was to BUILD the missing durable store (a migration + a real PgJobStore +
PgGateStore) inside the gate task, because deferring would let the gate certify hollow state. If your
anti-inflation gate can pass against fake/ephemeral state, the gate is weaker than the claim it certifies.

## 2. Adversarial refuse-surface suites (the red-team phase)

After hardening, run a dedicated **ADVERSARIAL** phase: independent suites (call them Z1…Zn) that each
*attack* one invariant and assert the system **refuses**. They are build-blind to the feature code and
depend on the real implementation surfaces, not on the hardening task's own tests. They caught bugs that
slices, hardening, AND the e2e gate all missed:

- **Cross-tenant authz bypass (P0):** call every `:tenant_id`-scoped route with a principal scoped to a
  *different* tenant; assert it's forbidden. The first pass caught one leaking route; a **directed
  re-audit of the WHOLE class** ("enumerate ALL `:tenant_id` routes, test each") caught a *second* P0 the
  first pass missed. Audit the whole class, not the one instance you tripped over.
- **Provenance/label smuggling:** try to write a record with a higher trust/provenance label than the
  caller is allowed to assert; assert the store clamps it to a ceiling.
- **Path traversal on a public path allowlist:** feed `..`/encoded segments to the "is this a public API
  path?" check; assert it doesn't escape the `/v1` prefix.
- **Spend / egress / TOCTOU / fail-open** invariants: attack each, assert refusal.

**How to run the phase:**
- One suite per invariant, each its own task/branch/PR, built by a fresh (build-blind) worker.
- A suite legitimately goes **P0-RED** when it finds a real hole. That is a *finding*, not a suite bug.
- **Fix the finding in-branch** (maintainer-authored fix + the suite stays as the regression), then
  **ratchet** it (§4). Don't split "found it" and "fixed it" across a merge unless the fix is large.
- Triage every finding: **P0** (security/data-integrity/authz — fix before ship, in-branch) vs **backlog**
  (hardening nicety, defense-in-depth — record in `backlog.md`, don't block the pipeline). Log the triage.

The canonical fix shape for the authz class (carry it forward):
```ts
import { hasTenantAccess } from '../../auth/scopes.js';
if (!hasTenantAccess(identity.scopes, tenantId, 'write')) throw errors.forbidden(tenantId);
```

## 3. Drift ratchets (contract ⇄ live surface)

A capability card / discovery doc that advertises tools the server no longer serves is a silent lie. Encode
a **drift ratchet**: a recorded snapshot of the *measured* live surface (e.g. `measured-surface.json`) that
a test compares against the *advertised* surface. Any task that adds/removes a route MUST update the record
in the same PR, or the ratchet reddens. This catches "capability card advertises tools that 404" — which no
per-feature test would catch, because each feature passes in isolation.

## 4. Ratcheting a fix (red-by-revert) — make regressions impossible to reintroduce

Every real finding gets a test that would go **red if the fix were reverted**. Prove it does: transiently
revert the one-line guard, watch the suite go red, restore it, watch it go green. An assertion that passes
both with and without the fix is worthless. Bake this into the fix task's acceptance: "show the suite reds
when the guard is removed." This is what converts a one-time catch into a permanent invariant.

## 5. Where these live in the lifecycle

```
… HARDENING → e2e TEST (anti-inflation gate, teeth) → ADVERSARIAL (Z-suites, fix-in-branch+ratchet) → SHIP
```

Do not let SHIP proceed while any P0 adversarial finding is open or any negative control can't red. The
whole point of this layer is that "all unit tests green" is the *start* of verification, not the end.

## 6. Operating this layer in CI — two traps that waste a whole cycle

These suites are subprocess-heavy (they shell out to gitleaks/scanners in loops) and deliberately noisy
(they plant violations to prove detectors fire). Both properties bite you when reading CI:

- **Deflake, don't re-run (gotcha #21).** A subprocess-in-a-loop test blows the runner's *default* per-test
  timeout on a loaded runner while passing on a sibling run — a `Test timed out`, not an assertion. Give
  those tests an explicit generous timeout up front (e.g. `120_000`); the assertion is unchanged so the
  invariant holds. Re-running masks the flake and lets it block the next promotion.
- **Read the FAIL marker, not the noise (gotcha #22).** A green fence/drift/refuse-surface run *prints* its
  planted violation text (`imports "@vendor" — allowed only in …`, `schema-drift … body: number`) on the
  happy path. Those lines sit inside tests marked ✓. Triage a failing log by the real `FAIL <file>` /
  `Tests N failed` / final `##[error]` markers, and identify the owning test id before you "fix" anything.
