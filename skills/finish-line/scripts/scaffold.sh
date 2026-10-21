#!/usr/bin/env bash
# scaffold.sh — Phase 0 setup of .finish/ in the product repo. Idempotent.
#
#   scaffold.sh [--web]
#
# Run anywhere inside the product repo. Creates what's missing, never
# overwrites your files:
#   .finish/STATUS (AUDITING) · SCOPE (P0) · PROGRESS.md · DECISIONS.md · OWNER_ACTIONS.md · LATER.md
#   .finish/RUN                        which skill version started this run (a .finish/ without it is
#                                      an older run, which finish.sh sets aside and starts fresh)
#   .finish/verify.sh                  gate template — fill every STAGE_*
#   .finish/bin/{ledger,tamper,lib}.sh vendored copies (refreshed until the ledger is frozen)
#   .claude/agents/finish-verifier.md  independent verifier subagent
#   .claude/settings.local.json        no permission prompts and no questions in interactive sessions
#                                      (allow the tools the protocol uses; deny AskUserQuestion, plan mode,
#                                      force-push, history rewrites, and the community-pack skills that
#                                      ask, plan, publish or merge — see references/companions.md)
#   .finish/companions.json            which installed community skills fill which protocol step
#   .gitignore entries for evidence, logs, companion state and browser-tool scratch dirs
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

put "$FD/RUN" "finish-line $(sed -n 's/^  version: "\(.*\)"$/\1/p' "$SKILL/SKILL.md" | head -1) · started $(fl_now)"
put "$FD/STATUS" "AUDITING"
put "$FD/SCOPE" "P0"
put "$FD/PROGRESS.md" "# Progress (append-only session log)"
put "$FD/DECISIONS.md" "# Decisions — what · why · reversible?"
put "$FD/OWNER_ACTIONS.md" "# Owner actions

Everything else is handled autonomously. Do these, then rerun finish.sh; each item reopens by itself once its check passes.

None."
put "$FD/LATER.md" "# Later — ideas and out-of-scope findings (never acted on during the run)"

if [[ -f "$FD/FREEZE" ]]; then
  for s in lib.sh ledger.sh tamper.sh; do
    cmp -s "$HERE/$s" "$FD/bin/$s" || echo "  ! $FD/bin/$s is older than the skill copy; finish.sh refreshes it and re-anchors the freeze on its next run"
  done
else
  for s in lib.sh ledger.sh tamper.sh; do
    if ! cmp -s "$HERE/$s" "$FD/bin/$s" 2>/dev/null; then cp "$HERE/$s" "$FD/bin/$s"; chmod 755 "$FD/bin/$s"; created "$FD/bin/$s"; fi
  done
fi

copy "$SKILL/templates/verify.sh" "$FD/verify.sh" 755
copy "$SKILL/templates/finish-verifier.md" ".claude/agents/finish-verifier.md"
if [[ -e .claude/settings.local.json ]]; then
  grep -q '"AskUserQuestion"' .claude/settings.local.json \
    || echo "  ! .claude/settings.local.json exists; merge $SKILL/templates/claude-settings.local.json into it so sessions never stop to ask"
else
  copy "$SKILL/templates/claude-settings.local.json" ".claude/settings.local.json"
fi
"$HERE/companions.sh" settings "$ROOT" | sed 's/^• /  ~ /'
[[ -f "$FD/companions.json" ]] || "$HERE/companions.sh" detect "$ROOT" | sed 's/^/  /'

if [[ $web -eq 1 ]]; then
  copy "$SKILL/templates/e2e/playwright.config.ts" "e2e/finish/playwright.config.ts"
  copy "$SKILL/templates/e2e/finish-fixture.ts" "e2e/finish/finish-fixture.ts"
fi

touch .gitignore
for line in '.finish/evidence/*' '!.finish/evidence/INDEX.md' '.finish/logs/' '.finish/ledger.proposed.json' '.finish/companions.json' '.claude/settings.local.json' '.env*.local' '.playwright-cli/' '.gstack/' 'test-results/' 'playwright-report/'; do
  if ! grep -qxF -- "$line" .gitignore; then
    if [[ -s .gitignore && -n "$(tail -c1 .gitignore)" ]]; then echo >> .gitignore; fi
    echo "$line" >> .gitignore
    created ".gitignore: $line"
  fi
done

echo "done. Next: fill .finish/verify.sh, write .finish/init.sh, commit: chore(finish): scaffold"
