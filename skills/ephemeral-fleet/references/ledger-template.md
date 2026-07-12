# Orchestration ledger (external brain) — ephemeral-fleet

Coordinator: re-read this file after every worker_done. Git is truth; this is the cache.
A lane whose sandbox died before the push is FAILED — never mark done from memory.

## Run meta
- Repo:
- BASE (integration branch):
- DEFAULT_BRANCH:
- Maintainer author:
- Started:
- Phase:
- Recipe name (`orca.yaml` environmentRecipes):
- Recipe doctor green? (Y/N + when):
- Parallel lanes N:

## Invariants
- [ ] Orca runtime up; orchestration experimental on; `orchestration` skill loaded
- [ ] BASE ≠ DEFAULT_BRANCH (preflight)
- [ ] No in-process Task/subagent substitutes for Orca dispatch
- [ ] We **use** Orca orchestration — we do not replace it
- [ ] Auth snapshot baked — no live credentials injected at dispatch
- [ ] Harvest (push / copy-out) BEFORE destroy on every lane
- [ ] Sandbox work enters BASE only via PR + review + merge-train

## Lanes
| lane | sandbox id | connection (orca-server\|ssh) | create ts | PROFILE | danger human grant? (ledger note / gate id) | work branch | pushed SHA | artifacts copied (paths) | destroy ts | provider verified gone? | status (DONE\|FAILED) |
|------|------------|-------------------------------|-----------|---------|---------------------------------------------|-------------|------------|--------------------------|------------|-------------------------|-----------------------|
| 1 | | | | ro\|rw\|danger | | `<maintainer>/lane-1` | | | | | |

Row done only when: pushed branch@sha visible on origin (or artifacts recorded), `worker_done` received, sandbox destroyed, destroy verified.

## Cost / standing check
- Any sandbox older than this run still alive? (finding if yes):

## Tasks
| id | title | deps | BUILT | PR_OPEN | REVIEWED | MERGED | WT_CLEAN | notes |
|----|-------|------|-------|---------|----------|--------|----------|-------|
| T1 | | — | f | f | f | f | f | |

## Gates
| gate | question | status | resolution |
|------|----------|--------|------------|

## Decisions
-

## Human / OPS queue
- [ ] Promotion PR BASE → default
- [ ] Deploy (if any) — MERGE ≠ DEPLOY
