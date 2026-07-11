# Diagnose-swarm — repro gates

## Gate A (hard stop)
No fix worker until `worker_done` from **Repro** includes:
- Exact command that goes **red** on this bug  
- Working directory / env notes  
- Observed failure rate (e.g. 8/10)  

If rate < ~20%, Repro continues raising flake rate (parallelism, stress, timing) — do not theorize.

## Gate B (optional bisect)
Only if red command is stable enough to automate. Bisect must use the **same** red command.

## Gate C (fix)
- Add regression test that fails if fix is reverted **before** or **with** the fix  
- Do not “retry until green”  

## Gate D (review)
Dual-axis / review-matrix; build-blind.

## Environmental failures
If repro is machine-specific: escalate via `decision_gate` with evidence — do not invent a product fix.
