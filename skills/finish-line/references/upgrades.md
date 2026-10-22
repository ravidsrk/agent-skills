# Checked gate and script upgrades

Stop all runners and interactive sessions before preparing an upgrade. A new
`ledger.sh specs` fails when any selected spec is missing. The old shipped gate
ignored that failure, received no paths and could print `GATE: PASS` while
skipping both the missing spec and existing selected specs. Updating bin alone
is unsafe. Scaffold and runner now check compatibility before distributing or
using the new scripts.

## Before the freeze

From the product repository, use the reviewed skill source:

```bash
"$FINISH_SKILL_DIR/scripts/upgrade-gate.sh" --check
"$FINISH_SKILL_DIR/scripts/upgrade-gate.sh" --propose > /tmp/finish-gate.proposed.sh
diff -u .finish/verify.sh /tmp/finish-gate.proposed.sh
"$FINISH_SKILL_DIR/scripts/upgrade-gate.sh" --apply
"$FINISH_SKILL_DIR/scripts/scaffold.sh"
./.finish/verify.sh
```

Review the proposal before applying it. The helper recognizes only the shipped
spec-selector function and adjacent legacy selection/empty branch. It replaces
one assignment with a checked assignment and failure exit. Every other gate
byte, configured `STAGE_*` command, stage list and file mode stays unchanged.
Current selectors are idempotent; unrecognized/custom selectors, duplicate calls,
symlinks and failed installations refuse without a success claim. A custom gate
needs a reviewed manual merge of equivalent failure handling, preserving its
commands. The conservative compatibility check may still refuse custom logic;
that needs an explicitly sanctioned migration, never a marker comment to bypass
recognition.

The helper's `--check` and `--propose` are read-only. `--apply` serializes its own
writes, refuses an occupied runner lock, stages and syntax-checks the repair,
and checks the original bytes and freeze-marker absence again before installation.
Keep other writers stopped; this is not a transaction against arbitrary concurrent
filesystem writers.

## Frozen runs

`--apply` refuses whenever `FREEZE` or `LEDGER.lock` is present, including orphan
or symlink markers. `--propose` can still print a read-only gate-only proposal.
For a legitimate frozen gate repair, follow the existing procedure in
[ledger.md §8](ledger.md): preserve the original gate and evidence,
review the exact diff, commit the gate change, request `ledger.sh amend --rebaseline`,
obtain the independent verifier's request-bound approval and apply that amendment.
Until the review/rebaseline succeeds the existing tamper failure stands. No helper
writes freeze markers, amendment records or bin during this process.

A gate amendment authorizes only that gate change. It does **not** authorize
refreshing frozen bin or moving its baseline. Runner and scaffold refuse any
frozen bin drift; the old automatic script refresh and runner reanchor are removed.
Continue with the matching reviewed skill version, prepare a separately sanctioned
migration outside the autonomous session, or explicitly start an archived fresh
run (`finish.sh --fresh`) and re-audit. This source does not implement an automatic
frozen-bin migration. Never copy new bin into a frozen run to get past the refusal,
and never call new source-ledger subcommands as an upgrade bypass.

Synthetic parser regressions under `tests/` reproduce the legacy false PASS,
exercise the copied gate with real script calls, retain full/quick selected-spec
execution and prove frozen/unknown/write-failure refusals. Their synthetic PASS or
APPROVE strings are not product verification or launch evidence.
