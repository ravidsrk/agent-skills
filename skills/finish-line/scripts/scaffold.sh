#!/usr/bin/env bash
# scaffold.sh — Phase 0 setup of .finish/ in the product repo. Idempotent.
#
#   scaffold.sh [--web]
#
# Run anywhere inside the product repo. Creates what's missing, never
# overwrites your files:
#   .finish/STATUS (AUDITING) · SCOPE (P0) · PROGRESS.md · DECISIONS.md · BLOCKERS.md · LATER.md
#   .finish/verify.sh                  gate template — fill every STAGE_*
#   .finish/bin/{ledger,tamper,lib}.sh vendored copies (refreshed until the ledger is frozen)
#   .claude/agents/finish-verifier.md  independent verifier subagent
#   .gitignore entries for evidence and logs
#   --web: e2e/finish/playwright.config.ts + e2e/finish/finish-fixture.ts

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git jq

web=0
for a in "$@"; do
  case "$a" in
    --web) web=1 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fl_die "unknown argument: $a" ;;
  esac
done

ROOT="$(fl_root)"
cd "$ROOT" || exit 2
FD=.finish

created() { echo "  + $1"; }
put() { # put <dest> <content>   (only if missing)
  if [[ ! -e "$1" ]]; then mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; created "$1"; fi
}
copy() { # copy <src> <dest> [mode]   (only if missing)
  if [[ ! -e "$2" ]]; then
    mkdir -p "$(dirname "$2")"; cp "$1" "$2"; [[ -n "${3:-}" ]] && chmod "$3" "$2"; created "$2"
  fi
}

echo "finish-line scaffold → $ROOT"
mkdir -p "$FD/evidence" "$FD/logs" "$FD/bin"

put "$FD/STATUS" "AUDITING"
put "$FD/SCOPE" "P0"
put "$FD/PROGRESS.md" "# Progress (append-only session log)"
put "$FD/DECISIONS.md" "# Decisions — what · why · reversible?"
put "$FD/BLOCKERS.md" "# Blockers
Format: - <ID> — <what is needed> — <exact steps for the human>
Human: when done, change the leading \"- \" to \"RESOLVED: \" and rerun."
put "$FD/LATER.md" "# Later — ideas and out-of-scope findings (never acted on during the run)"

if [[ -f "$FD/FREEZE" ]]; then
  for s in lib.sh ledger.sh tamper.sh; do
    cmp -s "$HERE/$s" "$FD/bin/$s" || echo "  ! $FD/bin/$s differs from the skill copy; ledger is frozen, so it was left alone (human: copy it and re-freeze)"
  done
else
  for s in lib.sh ledger.sh tamper.sh; do
    if ! cmp -s "$HERE/$s" "$FD/bin/$s" 2>/dev/null; then cp "$HERE/$s" "$FD/bin/$s"; chmod 755 "$FD/bin/$s"; created "$FD/bin/$s"; fi
  done
fi

copy "$SKILL/templates/verify.sh" "$FD/verify.sh" 755
copy "$SKILL/templates/finish-verifier.md" ".claude/agents/finish-verifier.md"

if [[ $web -eq 1 ]]; then
  copy "$SKILL/templates/e2e/playwright.config.ts" "e2e/finish/playwright.config.ts"
  copy "$SKILL/templates/e2e/finish-fixture.ts" "e2e/finish/finish-fixture.ts"
fi

touch .gitignore
for line in '.finish/evidence/*' '!.finish/evidence/INDEX.md' '.finish/logs/'; do
  if ! grep -qxF -- "$line" .gitignore; then
    if [[ -s .gitignore && -n "$(tail -c1 .gitignore)" ]]; then echo >> .gitignore; fi
    echo "$line" >> .gitignore
    created ".gitignore: $line"
  fi
done

echo "done. Next: fill .finish/verify.sh, write .finish/init.sh, commit: chore(finish): scaffold"
