#!/usr/bin/env bash
# finish.sh — unattended Finish Line runner. One fresh agent session per loop,
# until the product is LAUNCH_READY, BLOCKED_ON_HUMAN, stalled, out of budget,
# or a guard trips.
#
#   finish.sh [repo]                      default repo: current directory
#
# Env:
#   MAX_SESSIONS=40     hard cap on sessions (your compute budget)
#   STALL_LIMIT=3       stop after this many sessions without a new commit
#   CLAUDE_MODEL=       optional --model for claude
#   FINISH_AGENT=       alternative headless agent command; the prompt is
#                       appended as the last argument (default: claude -p)
#   FINISH_GIT_NAME / FINISH_GIT_EMAIL / FINISH_NO_AI_TRAILERS=1
#                       passed through to the agent (see references/protocol.md §9)
#
# Exit: 0 launch-ready or blocked on a human · 1 setup error · 2 stalled
#       3 session cap · 4 guard tripped (frozen files edited, ratchet lowered, tamper)
#
# The default agent runs with --dangerously-skip-permissions. Run this in a
# container, VM or a separate OS user with no production credentials.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
PROTOCOL="$SKILL/references/protocol.md"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"

case "${1:-}" in -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;; esac

REPO="${1:-$PWD}"
MAX_SESSIONS="${MAX_SESSIONS:-40}"
STALL_LIMIT="${STALL_LIMIT:-3}"

[[ -f "$PROTOCOL" ]] || { echo "missing $PROTOCOL"; exit 1; }
cd "$REPO" 2>/dev/null || { echo "no such directory: $REPO"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$REPO is not a git repository"; exit 1; }
cd "$(git rev-parse --show-toplevel)" || exit 1
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
if [[ -z "${FINISH_AGENT:-}" ]]; then
  command -v claude >/dev/null || { echo "claude CLI not found (or set FINISH_AGENT)"; exit 1; }
fi

mkdir -p .finish/logs
if ! mkdir .finish/logs/.runner.lock 2>/dev/null; then
  echo "another finish.sh is running here (stale? rmdir .finish/logs/.runner.lock)"; exit 1
fi
trap 'rmdir .finish/logs/.runner.lock 2>/dev/null' EXIT

export FINISH_SKILL_DIR="$SKILL"

head_sha() { git rev-parse HEAD 2>/dev/null || echo none; }
status_now() { tr -d '[:space:]' < .finish/STATUS 2>/dev/null || echo NEW; }
progress() { "$HERE/ledger.sh" status --line 2>/dev/null || echo "P0 ?"; }
guarded() { # hashes of files the agent must never change after the freeze
  local f
  for f in .finish/FREEZE .finish/LEDGER.lock .finish/bin/lib.sh .finish/bin/ledger.sh .finish/bin/tamper.sh; do
    if [[ -f "$f" ]]; then printf '%s %s\n' "$(fl_sha < "$f")" "$f"; else printf 'absent %s\n' "$f"; fi
  done
}

run_agent() {
  local prompt
  prompt="FINISH_SKILL_DIR=$SKILL
This is one session of an unattended Finish Line run. Follow the protocol below exactly, then end the session.

$(cat "$PROTOCOL")"
  if [[ -n "${FINISH_AGENT:-}" ]]; then
    # shellcheck disable=SC2086  # FINISH_AGENT is a command line; split it on purpose
    $FINISH_AGENT "$prompt"
  else
    local model=()
    [[ -n "${CLAUDE_MODEL:-}" ]] && model=(--model "$CLAUDE_MODEL")
    claude -p "$prompt" --dangerously-skip-permissions ${model[@]+"${model[@]}"}
  fi
}

trip() { echo "■ Guard tripped: $*"; echo "  Nothing was reverted. Inspect: git log -p -3 ; .finish/bin/ledger.sh check ; .finish/bin/tamper.sh"; exit 4; }

stall=0
last_head="$(head_sha)"

for ((i = 1; i <= MAX_SESSIONS; i++)); do
  log=".finish/logs/session-$(date +%Y%m%d-%H%M%S)-$i.log"
  echo "▶ Session $i/$MAX_SESSIONS · $(status_now) · $(progress) · log $log"

  frozen=0; [[ -f .finish/FREEZE ]] && frozen=1
  before_guard="$(guarded)"
  before_ratchet="$(cat .finish/ratchet.json 2>/dev/null || echo '{}')"

  run_agent 2>&1 | tee "$log"

  if [[ $frozen -eq 1 ]]; then
    [[ "$(guarded)" == "$before_guard" ]] || trip "the agent changed FREEZE, LEDGER.lock or .finish/bin/ during session $i"
    "$HERE/ledger.sh" check >/dev/null 2>&1 || trip "frozen ledger criteria were edited (ledger.sh check)"
    after_ratchet="$(cat .finish/ratchet.json 2>/dev/null || echo '{}')"
    jq -en --argjson a "$before_ratchet" --argjson b "$after_ratchet" \
      '[$a | to_entries[] | . as $e | ($b[$e.key].assertions // -1) >= $e.value.assertions] | all' >/dev/null 2>&1 \
      || trip "ratchet lowered: a passing spec lost assertions or was removed from .finish/ratchet.json"
    "$HERE/tamper.sh" > ".finish/logs/tamper-$i.txt" 2>&1 || { cat ".finish/logs/tamper-$i.txt"; trip "tamper.sh found gate gaming after session $i"; }
  fi

  [[ -z "$(git status --porcelain 2>/dev/null)" ]] || echo "⚠ working tree not clean after session $i (protocol requires a clean end)"

  st="$(status_now)"
  if [[ "$st" == "LAUNCH_READY" || "$st" == "BLOCKED_ON_HUMAN" ]]; then
    echo "■ $st · $(progress)"
    "$HERE/ledger.sh" status 2>/dev/null | sed 's/^/  /'
    echo "  Read .finish/LAUNCH_REPORT.md and .finish/BLOCKERS.md"
    exit 0
  fi

  h="$(head_sha)"
  if [[ "$h" == "$last_head" ]]; then
    stall=$((stall + 1))
    echo "⚠ no new commit this session ($stall/$STALL_LIMIT)"
    if [[ $stall -ge $STALL_LIMIT ]]; then
      echo "■ Stalled: $STALL_LIMIT sessions without a commit. Read $log and .finish/PROGRESS.md"
      exit 2
    fi
  else
    stall=0
    last_head="$h"
  fi
done

echo "■ Session cap MAX_SESSIONS=$MAX_SESSIONS reached · $(status_now) · $(progress)"
exit 3
