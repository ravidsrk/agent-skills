#!/usr/bin/env bash
# finish.sh — unattended, fully autonomous Finish Line runner. It never asks a
# question and never waits for a person mid-run. One fresh agent session per
# loop until the product is LAUNCH_READY, or READY_FOR_OWNER (only owner
# actions such as credentials remain, listed in .finish/OWNER_ACTIONS.md).
# It recovers on its own instead of stopping:
#   - a session that games the gate is reverted with new commits (uncommitted
#     work is stashed, nothing is lost) and the next session is told why
#   - STALL_LIMIT sessions without a commit pause the current item as stuck; an item is
#     never abandoned: when nothing else is failing, the runner reopens the least-tried
#     stuck item as its next research round (protocol §5.1) until it passes
#   - agent CLI failures are retried with exponential backoff
#   - owner actions are re-checked before every session; done ones reopen
#   - FINISH_UNTIL=P1 or P2 opens the next scope once P0 is done
#   - skill upgrades first check gate compatibility; frozen bin drift is refused
#     without a separately sanctioned migration or explicit archived fresh run
# Every session runs with a policy (--settings) that denies community skills which ask,
# plan, publish or merge, turns hooks off, and tells gstack nobody is there to answer.
# Its own commits contain only the files it changed, never anything else you staged.
#
#   finish.sh [--fresh] [repo]            default repo: current directory
#
# The runner works on the finish-line branch, checking it out if it exists. --fresh sets every
# previous run aside first (scripts/fresh.sh: archived, nothing deleted) and starts the review
# over from the docs. A run an older version of the skill started (no .finish/RUN) built its
# picture of the product without the checked brief; the runner starts those fresh on its own,
# unless FINISH_KEEP_RUN=1.
#
# Env:
#   MAX_SESSIONS=40          hard cap on sessions (your compute budget)
#   STALL_LIMIT=3            sessions without a commit before the item is paused (or a research round opens)
#   FINISH_MAX_DRY=9         consecutive sessions with no commit at all before the runner gives up (exit 2)
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
#   FINISH_KEEP_RUN=1        keep a run an older skill version started instead of starting fresh
#
# Exit: 0 LAUNCH_READY or READY_FOR_OWNER · 1 setup error · 2 the agent makes no commits at all
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

FRESH=0; REPO=""
for a in "$@"; do
  case "$a" in
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    --fresh) FRESH=1 ;;
    -*) echo "unknown option: $a (try --help)"; exit 1 ;;
    *) REPO="$a" ;;
  esac
done
REPO="${REPO:-$PWD}"
MAX_SESSIONS="${MAX_SESSIONS:-40}"
STALL_LIMIT="${STALL_LIMIT:-3}"
MAX_DRY="${FINISH_MAX_DRY:-$((STALL_LIMIT * 3))}"
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
  local msg="$1" p keep=(); shift
  for p in "$@"; do   # a path that neither exists nor is tracked would make git add refuse them all
    if [[ -e "$p" ]] || git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then keep+=("$p"); fi
  done
  [[ ${#keep[@]} -gt 0 ]] || return 0
  set -- "${keep[@]}"
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
# (grep -c reads everything: under pipefail, grep -q stopping early would fail git with SIGPIPE on a
# long status and read as clean.)
dirty() { [[ "$(git status --porcelain -uall -- . "${KEEP[@]}" 2>/dev/null | grep -cv ' \.finish/logs/')" -gt 0 ]]; }
stash() { git stash push -u -q -m "$1" -- . "${KEEP[@]}" && ! dirty; }

stash_local() {
  stash "finish-line: local changes before run $(date +%Y-%m-%dT%H:%M)" \
    || { echo "uncommitted changes could not be stashed; commit or stash them, then rerun"; exit 1; }
  echo "• stashed uncommitted changes before the run (restore with: git stash pop)"
}

# The run lives on finish-line (protocol §9): work there, so the checks below and every session
# see the run itself, not a copy merged into another branch. Switch before stashing: files that
# finish-line ignores (evidence, logs, local settings) show as untracked on other branches, and a
# stash would take them away from the run.
if git rev-parse -q --verify refs/heads/finish-line >/dev/null && [[ "$(git symbolic-ref -q --short HEAD)" != finish-line ]]; then
  if ! git checkout -q finish-line 2>/dev/null; then
    stash_local   # local changes that would be overwritten
    git checkout -q finish-line || { echo "could not check out the finish-line branch"; exit 1; }
  fi
  echo "• switched to the finish-line branch"
fi

# Check compatibility on the selected run branch before changing its run files.
[[ $FRESH -eq 1 ]] || "$HERE/upgrade-gate.sh" --check || exit 1

# Start from a clean tree: the run reverts by commit, so stash anything local first.
if dirty; then stash_local; fi

# A run an older version of the skill started (no .finish/RUN) understood the product without a
# brief checked against the docs. Everything it built rests on that reading, so it is set aside
# like --fresh.
legacy_run() { [[ -f .finish/STATUS && ! -f .finish/RUN ]]; }
if [[ $FRESH -eq 0 && "${FINISH_KEEP_RUN:-}" != 1 ]] && legacy_run; then
  echo "• this run was started by an older finish-line, before the product brief was checked against the docs: starting the review fresh (FINISH_KEEP_RUN=1 keeps it)"
  FRESH=1
fi
if [[ $FRESH -eq 1 ]]; then
  FINISH_FRESH_UNDER_RUNNER=1 FINISH_FRESH_PREFIX="• " "$HERE/fresh.sh" || { echo "■ the fresh start was refused (see above)"; exit 1; }
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
  for f in .finish/SCOPE .finish/RUN .finish/bin/lib.sh .finish/bin/ledger.sh .finish/bin/tamper.sh \
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
# Statuses that end work on an item can only come from ledger.sh: a session that moved an item to
# passing or needs_owner must have left what ledger.sh pass / owner --apply write. Hand-editing a
# status into ledger.json would otherwise skip every guard.
audit_statuses() { # <ledger at session start> → prints the first violation, exit 1
  local prev="$1" id to spec r req rev
  [[ -f "$prev" && -f .finish/ledger.json ]] || return 0
  while IFS=$'\t' read -r id _ to; do
    case "$to" in
      passing)
        r=".finish/evidence/$id/verifier/report.md"
        if ! { grep -Eq '^VERDICT: *PASS' "$r" 2>/dev/null && grep -Eq '^STATE: *[0-9a-f]{16,}' "$r" \
               && jq -e --arg id "$id" '.items[] | select(.id == $id) | ((.evidence | length) > 0 and ((.notes // "") | test("passed \\(verifier PASS\\)")))' .finish/ledger.json >/dev/null; }; then
          echo "$id was marked passing without ledger.sh pass (no verifier PASS report, evidence or pass record)"; return 1
        fi
        spec="$(jq -r --arg id "$id" '.items[] | select(.id == $id) | .verify.spec // empty' .finish/ledger.json)"
        if [[ -n "$spec" ]] && ! jq -e --arg id "$id" --arg s "$spec" '.[$id].spec == $s' .finish/ratchet.json >/dev/null 2>&1; then
          echo "$id was marked passing without ledger.sh pass (no ratchet entry for $spec)"; return 1
        fi ;;
      needs_owner)
        req=".finish/owner/$id.request.md"; rev=".finish/owner/$id.review.md"
        if ! { [[ -f "$req" && -f "$rev" ]] && grep -Eq "^REQUEST: *$(fl_sha < "$req")" "$rev" && grep -Eq '^VERDICT: *APPROVE' "$rev" \
               && jq -e --arg id "$id" 'has($id)' .finish/owner.json >/dev/null 2>&1; }; then
          echo "$id was handed to the owner without the verifier's approval (ledger.sh owner, then owner --apply)"; return 1
        fi ;;
    esac
  done < <(jq -r --slurpfile b "$prev" '($b[0].items | map({key: .id, value: .status}) | from_entries) as $B
      | .items[] | select(.status != ($B[.id] // "failing")) | "\(.id)\t\($B[.id] // "new")\t\(.status)"' .finish/ledger.json)
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
    claude --help 2>/dev/null | grep -- '--permission-prompts' >/dev/null && extra+=(--permission-prompts none)
    [[ -n "${CLAUDE_MODEL:-}" ]] && extra+=(--model "$CLAUDE_MODEL")
    [[ -n "$POLICY" ]] && extra+=(--settings "$POLICY")   # flag scope: outranks the repo's and the user's settings
    claude -p "$prompt" "${extra[@]}" < /dev/null
  fi
}

# Older products: migrate statuses, refresh an unmodified verifier, add the no-questions settings.
upgrade_project() {
  local out cur inst
  if [[ -f .finish/ledger.json ]]; then
    out="$("$HERE/ledger.sh" migrate 2>/dev/null)"
    case "$out" in *reopened*|*awaiting*) printf '%s\n' "$out" | sed 's/^/• /'; runner_commit "chore(finish): runner moves old hand-offs back into the run and sends unreviewed owner actions to the verifier" .finish/ledger.json .finish/owner.json .finish/OWNER_ACTIONS.md .finish/owner ;; esac
  fi
  if [[ -f .claude/agents/finish-verifier.md ]]; then
    cur="$(fl_sha < "$SKILL/templates/finish-verifier.md")"; inst="$(fl_sha < .claude/agents/finish-verifier.md)"
    if [[ "$inst" != "$cur" ]]; then
      if grep -qxF "$inst" "$SKILL/templates/finish-verifier.history" 2>/dev/null; then
        cp "$SKILL/templates/finish-verifier.md" .claude/agents/finish-verifier.md
        runner_commit "chore(finish): runner refreshes the verifier agent" .claude/agents/finish-verifier.md
        echo "• refreshed .claude/agents/finish-verifier.md"
      elif ! grep -q '^## Amendment mode' .claude/agents/finish-verifier.md || ! grep -q '^## Freeze mode' .claude/agents/finish-verifier.md; then
        echo "⚠ .claude/agents/finish-verifier.md is customised and lacks freeze or amendment mode; merge $SKILL/templates/finish-verifier.md into it"
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
# Nothing failing but something stuck: reopen the least-tried stuck item as its next research
# round, so the next session always has an unresolved item to work. Items are never abandoned.
open_round_if_idle() {
  local sid
  [[ -f .finish/FREEZE && "$(status_now)" == BUILDING ]] || return 0
  "$HERE/ledger.sh" next >/dev/null 2>&1 && return 0
  sid="$("$HERE/ledger.sh" next --stuck 2>/dev/null)" && [[ -n "$sid" ]] || return 0
  "$HERE/ledger.sh" round "$sid" >/dev/null || return 0
  runner_commit "chore(finish): runner opens a research round for $sid" .finish/ledger.json
  echo "• nothing else is failing: research round for $sid"
}

between_sessions() {
  local out st scope
  "$HERE/upgrade-gate.sh" --check || exit 1
  upgrade_project
  if [[ -f .finish/ledger.json && -f .finish/owner.json ]]; then
    out="$("$HERE/ledger.sh" owner-check 2>&1)"
    echo "• $out"
    case "$out" in *reopened*) runner_commit "chore(finish): owner action detected (${out#*reopened })" .finish ;; esac
  fi
  st="$(status_now)"
  is_terminal "$st" || { open_round_if_idle; return 0; }
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
    open_round_if_idle
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
dry=0       # consecutive sessions in which the agent committed nothing at all
agent_fail=0
trips=0

while :; do
  between_sessions
  if [[ $sessions -ge $MAX_SESSIONS ]]; then
    echo "■ Session cap MAX_SESSIONS=$MAX_SESSIONS reached · $(status_now) · $(progress)"
    "$HERE/ledger.sh" open 2>/dev/null | sed 's/^/  open — /'
    echo "  Nothing was abandoned: rerun with a higher MAX_SESSIONS to keep going; research so far is in .finish/research/"
    exit 3
  fi
  sessions=$((sessions + 1))
  log=".finish/logs/session-$(date +%Y%m%d-%H%M%S)-$sessions.log"
  echo "▶ Session $sessions/$MAX_SESSIONS · $(status_now) · $(progress) · log $log"

  start="$(head_sha)"
  frozen=0; [[ -f .finish/FREEZE ]] && frozen=1
  before_fixed="$(fixed)"
  had_run=0; [[ -f .finish/RUN ]] && had_run=1
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
    if [[ -z "$reason" ]] && ! out="$(audit_statuses "$GITDIR/finish-line.ledger.json")"; then
      reason="$out"
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
    # The first freeze rests on a brief the verifier checked against the docs, and on a ledger it approved.
    if [[ -z "$reason" ]] && ! out="$("$HERE/ledger.sh" freeze-check 2>&1)"; then
      reason="the session froze the ledger without the verifier's approval of the brief and the ledger ($out)"
    fi
  fi
  if [[ -z "$reason" && $had_run -eq 1 && ! -f .finish/RUN ]]; then
    reason="the session deleted .finish/RUN (it marks this run; only fresh.sh starts a new one)"
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
    stall=0
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
    [[ "$(head_sha)" == "$start" ]] || stall=0
    if is_terminal "$(status_now)"; then echo BUILDING > .finish/STATUS; runner_commit "chore(finish): runner discards STATUS from a failed session" .finish/STATUS; fi
    continue
  fi
  agent_fail=0
  is_terminal "$(status_now)" && claimed=1

  # Progress = the session's own commits. $start is taken after the runner's between-session
  # commits (owner checks, research rounds), so those never count as the agent's work.
  if [[ "$(head_sha)" != "$start" ]]; then stall=0; dry=0; continue; fi
  stall=$((stall + 1)); dry=$((dry + 1))
  echo "⚠ no new commit this session ($stall/$STALL_LIMIT)"
  if [[ $dry -ge $MAX_DRY ]]; then
    echo "■ $MAX_DRY sessions in a row committed nothing at all — not even research notes — so the agent isn't working (it can't run, or its CLI misbehaves). Read $log and .finish/PROGRESS.md"
    exit 2
  fi
  [[ $stall -ge $STALL_LIMIT ]] || continue
  id="$("$HERE/ledger.sh" next 2>/dev/null | head -1 | cut -f1)"
  if [[ -n "$id" && "$id" != "none" ]]; then
    "$HERE/ledger.sh" stuck "$id" "runner: $STALL_LIMIT sessions without a commit" >/dev/null
    note_progress "The runner paused $id as stuck after $STALL_LIMIT sessions without a commit. Take the next item; $id comes back as a research round (protocol §5.1)."
    runner_commit "chore(finish): runner pauses $id after $STALL_LIMIT sessions without progress" .finish
    echo "• paused $id as stuck"
  elif sid="$("$HERE/ledger.sh" next --stuck 2>/dev/null)" && [[ -n "$sid" ]]; then
    "$HERE/ledger.sh" round "$sid" >/dev/null
    note_progress "Nothing is failing and $STALL_LIMIT sessions made no commit, so the runner opened the next research round for $sid. Work it per protocol §5.1 and commit .finish/research/$sid.md every session, fixed or not."
    runner_commit "chore(finish): runner opens a research round for $sid" .finish
    echo "• research round for $sid"
  else
    echo "■ No progress possible: $STALL_LIMIT sessions without a commit and nothing in scope is failing or stuck. Read $log and .finish/PROGRESS.md"
    exit 2
  fi
  stall=0
done
