#!/usr/bin/env bash
# .finish/verify.sh — the Finish Line gate (installed by the finish-line skill).
#
#   ./.finish/verify.sh            full gate: every stage, every in-scope spec
#   ./.finish/verify.sh --quick    typecheck + specs of items already passing + tamper
#
# Fill EVERY STAGE_* below with a command, or "n/a: <reason>" when the stage
# truly doesn't apply to this repo. Empty = the gate fails. Turning a command
# into n/a after the ledger is frozen is flagged by tamper.sh.
#
# Spec stages (E2E_WEB, E2E_MOBILE, API) get their spec files from the ledger:
#   - the command is run once with all spec paths appended, or
#   - if the command contains {}, once per spec with {} replaced by the path.
# No specs yet → the stage is skipped.
#
# COMMANDS runs the ledger's `command` items (all in scope, or passing only
# with --quick). Command items must never call verify.sh themselves.
#
# After the freeze this file is locked: tamper.sh fails on any change except
# filling in a stage that was empty or n/a. Fill every stage in Phase 0.
#
# Commands per stack: references/verification.md in the finish-line skill.

# shellcheck disable=SC2034  # STAGE_* are read indirectly via ${!var}
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

STAGE_INSTALL=""      # clean install from the lockfile          e.g. npm ci
STAGE_TYPECHECK=""    # static types                             e.g. npx tsc --noEmit
STAGE_LINT=""         # linter                                   e.g. npx eslint .
STAGE_UNIT=""         # unit tests                               e.g. npx vitest run
STAGE_BUILD=""        # production build of every surface        e.g. npm run build
STAGE_E2E_WEB=""      # Playwright, spec paths appended          e.g. npx playwright test -c e2e/finish/playwright.config.ts
STAGE_E2E_MOBILE=""   # Maestro, one run per flow                e.g. maestro test {}
STAGE_API=""          # API tests against the running server     e.g. npx vitest run
STAGE_COMMANDS="./.finish/bin/ledger.sh run-commands"
STAGE_TAMPER="./.finish/bin/tamper.sh"
STAGE_SECRETS=""      # secrets scan, whole history              e.g. gitleaks git --no-banner
STAGE_DEPS=""         # dependency audit, fail on critical only  e.g. npm audit --audit-level=critical --omit=dev

FULL="INSTALL TYPECHECK LINT UNIT BUILD E2E_WEB E2E_MOBILE API COMMANDS TAMPER SECRETS DEPS"
QUICK="TYPECHECK E2E_WEB E2E_MOBILE API COMMANDS TAMPER"

mode=full; stages="$FULL"; passing_flag=""
if [[ "${1:-}" == "--quick" ]]; then mode=quick; stages="$QUICK"; passing_flag="--passing"; fi

ts="$(date +%Y%m%d-%H%M%S)"
mkdir -p .finish/evidence/_gate
summary=".finish/evidence/_gate/$ts-$mode.txt"
echo "verify.sh $mode · $(git rev-parse --short HEAD 2>/dev/null) · $ts" > "$summary"

specs_for() { # stage → spec paths from the ledger (in-scope; --passing in quick mode)
  local method
  case "$1" in E2E_WEB) method=e2e-web ;; E2E_MOBILE) method=e2e-mobile ;; API) method=api ;; *) return 0 ;; esac
  [[ -f .finish/ledger.json ]] || return 0
  # shellcheck disable=SC2086
  ./.finish/bin/ledger.sh specs $passing_flag --method "$method"
}

line() { printf '%-11s %-5s %4ss  %s\n' "$1" "$2" "$3" "$4" | tee -a "$summary"; }

for s in $stages; do
  var="STAGE_$s"
  cmd="${!var}"
  start=$SECONDS
  if [[ -z "$cmd" ]]; then
    line "$s" FAIL 0 "not configured — set $var to a command or \"n/a: <reason>\""
    echo "GATE: FAIL at $s" | tee -a "$summary"; exit 1
  fi
  if [[ "$cmd" == n/a* ]]; then reason="${cmd#n/a}"; reason="${reason#:}"; line "$s" N/A 0 "${reason# }"; continue; fi

  case "$s" in
    E2E_WEB|E2E_MOBILE|API)
      specs="$(specs_for "$s")"
      if [[ -z "$specs" ]]; then line "$s" SKIP 0 "no specs yet"; continue; fi
      rc=0
      if [[ "$cmd" == *"{}"* ]]; then
        while IFS= read -r spec; do
          echo "── $s: ${cmd//\{\}/$spec}"
          bash -c "${cmd//\{\}/$spec}" || { rc=1; break; }
        done <<< "$specs"
      else
        quoted=""
        while IFS= read -r spec; do quoted="$quoted $(printf '%q' "$spec")"; done <<< "$specs"
        echo "── $s: $cmd$quoted"
        bash -c "$cmd$quoted" || rc=1
      fi ;;
    COMMANDS)
      if [[ ! -f .finish/ledger.json ]]; then line "$s" SKIP 0 "no ledger yet"; continue; fi
      rc=0; bash -c "$cmd $passing_flag" || rc=1 ;;
    *)
      echo "── $s: $cmd"
      rc=0; bash -c "$cmd" || rc=1 ;;
  esac

  if [[ $rc -ne 0 ]]; then
    line "$s" FAIL $((SECONDS - start)) "$cmd"
    echo "GATE: FAIL at $s" | tee -a "$summary"; exit 1
  fi
  line "$s" PASS $((SECONDS - start)) "$cmd"
done

echo "GATE: PASS ($mode)" | tee -a "$summary"
