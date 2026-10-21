#!/usr/bin/env bash
# finish.sh — unattended, fully autonomous Finish Line runner. It never asks a
# question and never waits for a person mid-run. One fresh agent session per
# loop until the product is LAUNCH_READY, or READY_FOR_OWNER (only owner
# actions such as credentials remain, listed in .finish/OWNER_ACTIONS.md).
# It recovers on its own instead of stopping:
#   - a session that games the gate is reverted with new commits (uncommitted
#     work is stashed, nothing is lost) and the next session is told why
#   - STALL_LIMIT sessions without a commit park the current item as stuck
#   - agent CLI failures are retried with exponential backoff
#   - owner actions are re-checked before every session; done ones reopen
#   - FINISH_UNTIL=P1 or P2 opens the next scope once P0 is done
#   - after a skill upgrade it refreshes .finish/bin/ (re-anchoring the freeze), an
#     unmodified verifier agent and old statuses itself
# Every session runs with a policy (--settings) that denies community skills which ask,
# plan, publish or merge, turns hooks off, and tells gstack nobody is there to answer.
# Its own commits contain only the files it changed, never anything else you staged.
#
#   finish.sh [repo]                      default repo: current directory
#
# Env:
#   MAX_SESSIONS=40          hard cap on sessions (your compute budget)
#   STALL_LIMIT=3            sessions without a commit before the item is parked
#   FINISH_UNTIL=P0          keep going through P1 / P2 after P0 is done
#   FINISH_MAX_TRIPS=3       reverted sessions allowed before giving up
#   FINISH_MAX_AMENDMENTS=5  verifier-approved weakening amendments allowed
#   FINISH_BACKOFF=60        first retry delay (s) after an agent CLI failure; doubles, max 900
#   FINISH_OWNER_CHECK_TIMEOUT=60  seconds each owner-action check may run
#   CLAUDE_MODEL=            optional --model for claude
#   FINISH_AGENT=            other headless agent command; the prompt is appended as the last argument
#   FINISH_GIT_NAME / FINISH_GIT_EMAIL / FINISH_NO_AI_TRAILERS=1   commit identity and trailers
#   FINISH_COMPANIONS=auto   use installed community skill packs at their protocol steps
#                            (references/companions.md); off = never; install = install the
#                            recommended pinned packs first. Default off with FINISH_AGENT.
#   FINISH_KEEP_HOOKS=1      leave Claude Code hooks on (default: off for every session)
#
# Exit: 0 LAUNCH_READY or READY_FOR_OWNER · 1 setup error · 2 no progress possible
#       3 session cap · 4 too many reverted sessions · 5 agent CLI keeps failing
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
MAX_TRIPS="${FINISH_MAX_TRIPS:-3}"
BACKOFF="${FINISH_BACKOFF:-60}"
case "${FINISH_UNTIL:-P0}" in P1) UNTIL=1 ;; P2) UNTIL=2 ;; *) UNTIL=0 ;; esac

[[ -f "$PROTOCOL" ]] || { echo "missing $PROTOCOL"; exit 1; }
cd "$REPO" 2>/dev/null || { echo "no such directory: $REPO"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "$REPO is not a git repository"; exit 1; }
cd "$(git rev-parse --show-toplevel)" || exit 1
command -v jq >/dev/null || { echo "jq is required"; exit 1; }
if [[ -z "${FINISH_AGENT:-}" ]]; then
  command -v claude >/dev/null || { echo "claude CLI not found (or set FINISH_AGENT)"; exit 1; }
fi

gitc() { # git with the configured identity, if one was given
  if [[ -n "${FINISH_GIT_NAME:-}" && -n "${FINISH_GIT_EMAIL:-}" ]]; then
    git -c user.name="$FINISH_GIT_NAME" -c user.email="$FINISH_GIT_EMAIL" "$@"
  else
    git "$@"
  fi
}
runner_commit() { # runner_commit "<message>" <paths…> — commits only these paths, never anything else staged
  local msg="$1"; shift
  git add -A -- "$@" 2>/dev/null
  git diff --cached --quiet -- "$@" && return 0
  gitc commit -q -m "$msg" -- "$@" || echo "⚠ runner could not commit ($msg); the next session will"
}

GITDIR="$(cd "$(git rev-parse --git-dir)" && pwd)"
LOCK="$GITDIR/finish-line.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "another finish.sh is running in this repo (stale? rmdir $LOCK)"; exit 1
fi
SNAP="$GITDIR/finish-line.snapshot"
trap 'rmdir "$LOCK" 2>/dev/null; rm -f "$GITDIR/finish-line.ledger.json"; rm -rf "$SNAP"' EXIT

# Env files are where owner actions put keys: a stash must never take them.
# (Literal excludes of ignored paths make `git stash push` fail, so logs are filtered separately.)
KEEP=(':(exclude,glob)**/.env' ':(exclude,glob)**/.env.*')
dirty() { git status --porcelain -uall -- . "${KEEP[@]}" 2>/dev/null | grep -qv ' \.finish/logs/'; }
stash() { git stash push -u -q -m "$1" -- . "${KEEP[@]}" && ! dirty; }

# Start from a clean tree: the run reverts by commit, so stash anything local first.
if dirty; then
  stash "finish-line: local changes before run $(date +%Y-%m-%dT%H:%M)" \
    || { echo "uncommitted changes could not be stashed; commit or stash them, then rerun"; exit 1; }
  echo "• stashed uncommitted changes before the run (restore with: git stash pop)"
fi

mkdir -p .finish/logs

export FINISH_SKILL_DIR="$SKILL"

# Companion skills: record which installed packs fill which protocol step (the session
# reads .finish/companions.json), and build the policy every session runs under.
export GSTACK_SESSION_KIND=spawned   # gstack: never ask, take the recommended option, log it
COMPANIONS="${FINISH_COMPANIONS:-}"
[[ -n "$COMPANIONS" ]] || { if [[ -n "${FINISH_AGENT:-}" ]]; then COMPANIONS=off; else COMPANIONS=auto; fi; }
if [[ "$COMPANIONS" == install ]]; then
  FINISH_COMPANIONS=install "$HERE/companions.sh" install || echo "⚠ some companion packs did not install; using what is there"
else
  FINISH_COMPANIONS="$COMPANIONS" "$HERE/companions.sh" detect "$PWD" || echo "⚠ companion detection failed; sessions use the built-in steps"
fi
POLICY="$("$HERE/companions.sh" policy --runner 2>/dev/null)" || POLICY=""
[[ -n "$POLICY" ]] || echo "⚠ could not build the session policy (companions/catalog.json); running without it"
"$HERE/companions.sh" settings "$PWD" || true   # interactive sessions in this repo get the same deny list

head_sha() { git rev-parse HEAD 2>/dev/null || echo none; }
status_now() { tr -d '[:space:]' 2>/dev/null < .finish/STATUS || echo NEW; }
is_terminal() { case "$1" in LAUNCH_READY|READY_FOR_OWNER|BLOCKED_ON_HUMAN) return 0 ;; esac; return 1; }
progress() { "$HERE/ledger.sh" status --line 2>/dev/null || echo "P0 ?"; }
VERIFIER=.claude/agents/finish-verifier.md
GUARDED=("$VERIFIER" .claude/settings.json .claude/settings.local.json)   # only the runner or the owner changes these
fixed() { # files the agent must never change during a frozen session (FREEZE/LEDGER.lock move only by amendment)
  local f
  for f in .finish/SCOPE .finish/bin/lib.sh .finish/bin/ledger.sh .finish/bin/tamper.sh \
           "${GUARDED[@]}"; do
    if [[ -f "$f" ]]; then printf '%s %s\n' "$(fl_sha < "$f")" "$f"; else printf 'absent %s\n' "$f"; fi
  done
}
changed_fixed() { # <before> <after> → the fixed files that differ, space-separated
  diff <(printf '%s\n' "$1") <(printf '%s\n' "$2") | sed -n 's/^> [^ ]* //p' | tr '\n' ' ' | sed 's/ $//'
}
snapshot() { # copy the guarded files: a gitignored one would survive both the revert and the stash
  local f
  rm -rf "$SNAP"; mkdir -p "$SNAP"
  for f in "${GUARDED[@]}"; do
    [[ -f "$f" ]] && { mkdir -p "$SNAP/$(dirname "$f")"; cp "$f" "$SNAP/$f"; }
  done
}
restore_snapshot() { # put the guarded files back as they were before the session
  local f
  for f in "${GUARDED[@]}"; do
    if [[ -f "$SNAP/$f" ]]; then
      cmp -s "$SNAP/$f" "$f" 2>/dev/null || { mkdir -p "$(dirname "$f")"; cp "$SNAP/$f" "$f"; }
    else
      rm -f "$f"
    fi
  done
}
verifier_shipped() { # the installed verifier is one this skill shipped (not one a session wrote)
  [[ -f "$VERIFIER" ]] || return 0
  local h; h="$(fl_sha < "$VERIFIER")"
  [[ "$h" == "$(fl_sha < "$SKILL/templates/finish-verifier.md")" ]] || grep -qxF "$h" "$SKILL/templates/finish-verifier.history" 2>/dev/null
}
read_or() { tr -d '[:space:]' 2>/dev/null < "$1" || printf '%s' "$2"; }
amd_count() { cat .finish/amendments.jsonl 2>/dev/null | wc -l | tr -d ' '; }

run_agent() {
  local prompt
  prompt="FINISH_SKILL_DIR=$SKILL
This is one session of an unattended, fully autonomous Finish Line run. No human is watching and nobody will answer: never ask a question, never wait for confirmation, never offer options. Decide with the protocol's decision rules, log the decision, and keep going. Follow the protocol below exactly, then end the session.

$(cat "$PROTOCOL")"
  if [[ -n "${FINISH_AGENT:-}" ]]; then
    # shellcheck disable=SC2086  # FINISH_AGENT is a command line; split it on purpose
    $FINISH_AGENT "$prompt" < /dev/null
  else
    local extra=(--dangerously-skip-permissions --disallowedTools "AskUserQuestion,EnterPlanMode,ExitPlanMode")
    claude --help 2>/dev/null | grep -q -- '--permission-prompts' && extra+=(--permission-prompts none)
    [[ -n "${CLAUDE_MODEL:-}" ]] && extra+=(--model "$CLAUDE_MODEL")
    [[ -n "$POLICY" ]] && extra+=(--settings "$POLICY")   # flag scope: outranks the repo's and the user's settings
    claude -p "$prompt" "${extra[@]}" < /dev/null
  fi
}

# The skill was upgraded since the freeze: refresh the vendored scripts and move FREEZE
# past that commit, logged as a runner amendment (sessions can never log one themselves).
upgrade_bin() {
  [[ -f .finish/FREEZE && -d .finish/bin ]] || return 0
  local s stale=0 lock fb
  for s in lib.sh ledger.sh tamper.sh; do cmp -s "$HERE/$s" ".finish/bin/$s" || stale=1; done
  [[ $stale -eq 1 ]] || return 0
  # Only re-anchor a clean state, so nothing flagged can slip into the new baseline.
  "$HERE/tamper.sh" >/dev/null 2>&1 || { echo "⚠ skill scripts are newer than .finish/bin, but tamper.sh isn't clean; not refreshing yet"; return 0; }
  for s in lib.sh ledger.sh tamper.sh; do cp "$HERE/$s" ".finish/bin/$s"; chmod 755 ".finish/bin/$s"; done
  runner_commit "chore(finish): runner refreshes vendored scripts from the skill" .finish/bin || return 0
  fb="$(read_or .finish/FREEZE none)"; lock="$(read_or .finish/LEDGER.lock none)"
  git rev-parse HEAD > .finish/FREEZE
  jq -cn --arg n "$(printf '%03d' $(( $(amd_count) + 1 )))" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg l "$lock" --arg fb "$fb" --arg fa "$(cat .finish/FREEZE)" \
    '{n: $n, at: $at, kind: "upgrade", class: "runner", reason: "skill scripts refreshed by the runner", lock_before: $l, lock_after: $l,
      freeze_before: $fb, freeze_after: $fa, request: null, review: null}' >> .finish/amendments.jsonl
  runner_commit "chore(finish): runner re-anchors the freeze after the script refresh" .finish/FREEZE .finish/amendments.jsonl
  echo "• refreshed .finish/bin from the skill and re-anchored the freeze"
}

# Older products: migrate statuses, refresh an unmodified verifier, add the no-questions settings.
upgrade_project() {
  local out cur inst
  if [[ -f .finish/ledger.json ]]; then
    out="$("$HERE/ledger.sh" migrate 2>/dev/null)"
    case "$out" in *reopened*) echo "• $out"; runner_commit "chore(finish): runner migrates blocked items to the owner-action flow" .finish/ledger.json ;; esac
  fi
  if [[ -f .claude/agents/finish-verifier.md ]]; then
    cur="$(fl_sha < "$SKILL/templates/finish-verifier.md")"; inst="$(fl_sha < .claude/agents/finish-verifier.md)"
    if [[ "$inst" != "$cur" ]]; then
      if grep -qxF "$inst" "$SKILL/templates/finish-verifier.history" 2>/dev/null; then
        cp "$SKILL/templates/finish-verifier.md" .claude/agents/finish-verifier.md
        runner_commit "chore(finish): runner refreshes the verifier agent" .claude/agents/finish-verifier.md
        echo "• refreshed .claude/agents/finish-verifier.md"
      elif ! grep -q '^## Amendment mode' .claude/agents/finish-verifier.md; then
        echo "⚠ .claude/agents/finish-verifier.md is customised and has no amendment mode; merge $SKILL/templates/finish-verifier.md into it"
      fi
    fi
  fi
  if [[ -d .finish ]]; then
    local line added=0
    touch .gitignore
    for line in '.claude/settings.local.json' '.env*.local' '.finish/ledger.proposed.json' '.finish/companions.json' '.gstack/'; do
      grep -qxF -- "$line" .gitignore || { [[ -s .gitignore && -n "$(tail -c1 .gitignore)" ]] && echo >> .gitignore; echo "$line" >> .gitignore; added=1; }
    done
    [[ $added -eq 0 ]] || runner_commit "chore(finish): runner adds ignore rules for local settings, env files and tool state" .gitignore
  fi
  if [[ -d .claude && ! -e .claude/settings.local.json ]]; then
    cp "$SKILL/templates/claude-settings.local.json" .claude/settings.local.json
    "$HERE/companions.sh" settings "$PWD" >/dev/null 2>&1 || true
    echo "• added .claude/settings.local.json (no permission prompts or questions in interactive sessions)"
  fi
}

# Between sessions: reopen owner actions that are done, move past terminal states.
# Exits 0 when the run is complete.
between_sessions() {
  local out st scope
  upgrade_project
  upgrade_bin
  if [[ -f .finish/ledger.json && -f .finish/owner.json ]]; then
    out="$("$HERE/ledger.sh" owner-check 2>&1)"
    echo "• $out"
    case "$out" in *reopened*) runner_commit "chore(finish): owner action detected (${out#*reopened })" .finish ;; esac
  fi
  st="$(status_now)"
  is_terminal "$st" || return 0
  # The ledger, not the agent, decides whether the product is done.
  local verdict
  verdict="$("$HERE/ledger.sh" done-check 2>/dev/null || true)"
  if [[ "$verdict" != "LAUNCH_READY" && "$verdict" != "READY_FOR_OWNER" ]]; then
    if [[ $claimed -eq 1 ]]; then
      trips=$((trips + 1))
      echo "↺ STATUS=$st rejected ($trips/$MAX_TRIPS): ledger says ${verdict:-no ledger}"
      note_progress "The runner rejected STATUS=$st: the ledger says ${verdict:-no ledger}. A terminal status is only valid when ledger.sh done-check prints it."
      [[ $trips -lt $MAX_TRIPS ]] || { echo "■ $MAX_TRIPS false or reverted completions; stopping. See .finish/PROGRESS.md"; exit 4; }
    fi
    echo BUILDING > .finish/STATUS
    runner_commit "chore(finish): runner resumes building — ${verdict:-no ledger}" .finish/STATUS .finish/PROGRESS.md
    claimed=0
    return 0
  fi
  st="$verdict"; echo "$st" > .finish/STATUS
  claimed=0
  scope="$(fl_scope_n .finish)"
  if [[ $scope -lt $UNTIL ]]; then
    echo "P$((scope + 1))" > .finish/SCOPE
    echo BUILDING > .finish/STATUS
    runner_commit "chore(finish): runner opens P$((scope + 1)) scope (FINISH_UNTIL=P$UNTIL)" .finish/SCOPE .finish/STATUS
    echo "• opened scope P$((scope + 1))"
    return 0
  fi
  echo "■ $st · $(progress)"
  "$HERE/ledger.sh" status 2>/dev/null | sed 's/^/  /'
  echo "  Report: .finish/LAUNCH_REPORT.md · owner actions (if any): .finish/OWNER_ACTIONS.md"
  exit 0
}

note_progress() { printf '\n## Runner — %s\n%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$1" >> .finish/PROGRESS.md; }

revert_session() { # revert_session <start sha> <reason>
  local start="$1" reason="$2"
  if dirty && ! stash "finish-line: session $sessions tripped"; then
    echo "■ Could not set aside the uncommitted changes of session $sessions ($reason). Inspect: git status"
    exit 4
  fi
  if [[ "$(head_sha)" != "$start" ]]; then
    if ! gitc revert --no-edit "$start..HEAD" >/dev/null 2>&1; then
      git revert --abort >/dev/null 2>&1
      echo "■ Could not revert session $sessions automatically ($reason). Inspect: git log -p $start..HEAD"
      exit 4
    fi
  fi
  restore_snapshot
  mkdir -p .finish
  note_progress "Session $sessions was reverted by the runner: $reason
Do not repeat it. Details: .finish/logs/tamper-$sessions.txt and .finish/logs/$(basename "$log")"
  runner_commit "chore(finish): runner reverted session $sessions" .finish/PROGRESS.md
}

sessions=0
claimed=0   # 1 when the last session itself wrote a terminal STATUS
stall=0
agent_fail=0
trips=0
last_head="$(head_sha)"

while :; do
  between_sessions
  if [[ $sessions -ge $MAX_SESSIONS ]]; then
    echo "■ Session cap MAX_SESSIONS=$MAX_SESSIONS reached · $(status_now) · $(progress)"
    exit 3
  fi
  sessions=$((sessions + 1))
  log=".finish/logs/session-$(date +%Y%m%d-%H%M%S)-$sessions.log"
  echo "▶ Session $sessions/$MAX_SESSIONS · $(status_now) · $(progress) · log $log"

  start="$(head_sha)"
  frozen=0; [[ -f .finish/FREEZE ]] && frozen=1
  before_fixed="$(fixed)"
  before_lock="$(read_or .finish/LEDGER.lock none)"
  before_freeze="$(read_or .finish/FREEZE none)"
  before_amd="$(amd_count)"
  before_ratchet="$(cat .finish/ratchet.json 2>/dev/null || echo '{}')"
  snapshot
  cp .finish/ledger.json "$GITDIR/finish-line.ledger.json" 2>/dev/null || rm -f "$GITDIR/finish-line.ledger.json"

  run_agent 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}

  reason=""
  if [[ $frozen -eq 1 ]]; then
    ch="$(changed_fixed "$before_fixed" "$(fixed)")"
    [[ -z "$ch" ]] || reason="the session changed $ch (only the runner or the owner may)"
    if [[ -z "$reason" ]] && ! out="$("$HERE/ledger.sh" amend-verify "$before_lock" "$before_freeze" "$before_amd" "$GITDIR/finish-line.ledger.json" 2>&1)"; then
      reason="unapproved change to the frozen definition of done ($out)"
    fi
    if [[ -z "$reason" ]] && ! jq -en --argjson a "$before_ratchet" --argjson b "$(cat .finish/ratchet.json 2>/dev/null || echo '{}')" \
      '[$a | to_entries[] | . as $e | ($b[$e.key].assertions // -1) >= $e.value.assertions] | all' >/dev/null 2>&1; then
      reason="a passing spec's ratchet entry was lowered or removed"
    fi
  elif [[ -f .finish/FREEZE ]]; then
    # Froze during this session: vendored scripts it touched must be the skill's own
    # copies, and SCOPE may only have been created with the default P0.
    for s in lib.sh ledger.sh tamper.sh; do
      if ! printf '%s\n' "$before_fixed" | grep -qxF "$(fl_sha 2>/dev/null < ".finish/bin/$s") .finish/bin/$s"; then
        cmp -s "$HERE/$s" ".finish/bin/$s" || reason="the session froze the ledger with a modified .finish/bin/$s"
      fi
    done
    scope_before="$(printf '%s\n' "$before_fixed" | grep ' .finish/SCOPE$')"
    scope_after="$(fixed | grep ' .finish/SCOPE$')"
    if [[ "$scope_before" != "$scope_after" ]] && ! [[ "$scope_before" == "absent .finish/SCOPE" && "$(read_or .finish/SCOPE '')" == "P0" ]]; then
      reason="the session changed .finish/SCOPE"
    fi
  fi
  if [[ -z "$reason" && $frozen -eq 0 ]] && [[ " $(changed_fixed "$before_fixed" "$(fixed)") " == *" $VERIFIER "* ]] && ! verifier_shipped; then
    reason="the session wrote its own $VERIFIER; the verifier must be the one the skill ships (owners customise it between runs)"
  fi
  if [[ -z "$reason" && -f .finish/FREEZE ]]; then
    "$HERE/ledger.sh" check >/dev/null 2>&1 || reason="frozen criteria were hand-edited (ledger.sh check)"
  fi
  if [[ -z "$reason" && -f .finish/FREEZE ]]; then
    "$HERE/tamper.sh" > ".finish/logs/tamper-$sessions.txt" 2>&1 || reason="tamper.sh: $(grep -m1 '^TAMPER: [^FC]' ".finish/logs/tamper-$sessions.txt" | sed 's/^TAMPER: //')"
  fi

  if [[ -n "$reason" ]]; then
    trips=$((trips + 1))
    echo "↺ Session $sessions reverted ($trips/$MAX_TRIPS): $reason"
    revert_session "$start" "$reason"
    if [[ $trips -ge $MAX_TRIPS ]]; then
      echo "■ $MAX_TRIPS sessions had to be reverted; stopping so the pattern can be looked at. See .finish/PROGRESS.md"
      exit 4
    fi
    last_head="$(head_sha)"; stall=0
    continue
  fi

  dirty && echo "⚠ working tree not clean after session $sessions"

  if [[ $rc -ne 0 ]]; then
    # A failed session proves nothing, so a terminal STATUS it may have written doesn't count yet.
    agent_fail=$((agent_fail + 1))
    if [[ $agent_fail -ge $STALL_LIMIT ]]; then
      echo "■ The agent CLI exited non-zero $STALL_LIMIT sessions in a row (last: $rc). Read $log"
      exit 5
    fi
    wait_s=$((BACKOFF * (1 << (agent_fail - 1)))); [[ $wait_s -le 900 ]] || wait_s=900
    echo "⚠ agent exited $rc ($agent_fail/$STALL_LIMIT); retrying in ${wait_s}s"
    sleep "$wait_s"
    h="$(head_sha)"; [[ "$h" == "$last_head" ]] || { stall=0; last_head="$h"; }
    if is_terminal "$(status_now)"; then echo BUILDING > .finish/STATUS; runner_commit "chore(finish): runner discards STATUS from a failed session" .finish/STATUS; fi
    continue
  fi
  agent_fail=0
  is_terminal "$(status_now)" && claimed=1

  h="$(head_sha)"
  if [[ "$h" != "$last_head" ]]; then stall=0; last_head="$h"; continue; fi
  stall=$((stall + 1))
  echo "⚠ no new commit this session ($stall/$STALL_LIMIT)"
  [[ $stall -ge $STALL_LIMIT ]] || continue
  id="$("$HERE/ledger.sh" next 2>/dev/null | head -1 | cut -f1)"
  if [[ -z "$id" || "$id" == "none" ]]; then
    echo "■ No progress possible: $STALL_LIMIT sessions without a commit and no item to park. Read $log and .finish/PROGRESS.md"
    exit 2
  fi
  "$HERE/ledger.sh" stuck "$id" "runner: $STALL_LIMIT sessions without a commit" >/dev/null
  note_progress "The runner parked $id as stuck after $STALL_LIMIT sessions without a commit. Take the next item; $id gets its second round later."
  runner_commit "chore(finish): runner parked $id after $STALL_LIMIT sessions without progress" .finish
  echo "• parked $id as stuck"
  stall=0; last_head="$(head_sha)"
done
