#!/usr/bin/env bash
# spawn_worker.sh — reliable Orca worker dispatch for the clean-sweep coordinator.
#
# Works around the failure mode where `orca ... dispatch --inject` PASTES the prompt into a
# claude worker's input box but never SUBMITS it (codex auto-submits, claude does not). Flow:
#   create terminal -> wait tui-idle -> settle -> task-update ready -> dispatch --inject
#   -> Enter (submit) -> verify heartbeat, re-Enter up to 3x.
#
# Usage:
#   SP=<scratchpad_dir> spawn_worker.sh <task_id> <worktree_selector> <title> <agent: claude|codex> [effort]
# Prints:  HANDLE=<h> HB=<ts|None>
#
# NOTE: <worktree_selector> is a RAW orca selector. Orca worktree IDs are composite `uuid::path`, and
#   `--worktree id:<uuid>` fails with selector_not_found — pass `path:/abs/worktree/path` instead
#   (unambiguous), or the full `id:<uuid::path>` composite. See references/learnings.md #23.
#
# Env:
#   SP      scratchpad dir for the terminal-create JSON (default: cwd)
#   CLAUDE_CMD / CODEX_CMD  override the worker launch command (see SKILL.md "Worker roster" for
#                            the canonical --dangerously-* + max-effort flags baked in by default)
set -euo pipefail

SP="${SP:-$(pwd)}"
task="${1:?usage: SP=<dir> spawn_worker.sh <task_id> <worktree_selector> <title> <agent> [effort]}"
sel="${2:?worktree_selector required (e.g. path:/abs/path)}"
title="${3:?title required}"
agent="${4:-claude}"
effort="${5:-xhigh}"

CODEX_CMD="${CODEX_CMD:-codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort=\"$effort\"}"
CLAUDE_CMD="${CLAUDE_CMD:-claude --dangerously-skip-permissions}"

if [ "$agent" = "codex" ]; then cmd="$CODEX_CMD"; else cmd="$CLAUDE_CMD"; fi

# Sanitize title into an fs-safe slug (letters, digits, hyphen, underscore, dot) so it can't
# escape the scratchpad path or inject shell/quote characters into downstream tooling; append
# $$ so parallel spawns with identical titles cannot clobber each other. Covers M-2 + m-4.
slug=$(printf '%s' "$title" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)
tj="$SP/sw-${slug}.$$.json"

# EXIT trap: if we never confirmed a heartbeat, kill the terminal we created so an interrupted
# spawn doesn't leak orca terminals. Covers m-5.
h=""
hb=None
cleanup() {
  rc=$?
  if [ -n "$h" ] && [ "$hb" = "None" ]; then
    orca terminal kill --terminal "$h" --json >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# Create the terminal; check the exit code explicitly before parsing the JSON blob (covers M-3).
if ! orca terminal create --worktree "$sel" --title "$title" --command "$cmd" --json > "$tj" 2>&1; then
  echo "spawn_worker: orca terminal create failed:" >&2
  cat "$tj" >&2
  exit 1
fi

# Parse the terminal handle via argv (no shell interpolation into the Python literal). Covers M-2.
h=$(python3 - "$tj" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    r = d.get('result', d) if isinstance(d, dict) else {}
    term = r.get('terminal', {}) if isinstance(r, dict) else {}
    handle = term.get('handle') or r.get('handle') or ''
    print(handle)
except Exception as e:
    print('', end='')
    print(f'spawn_worker: could not parse terminal-create JSON: {e}', file=sys.stderr)
PY
)
if [ -z "$h" ]; then
  echo "spawn_worker: no terminal handle in $tj" >&2
  exit 1
fi

orca terminal wait --terminal "$h" --for tui-idle --timeout-ms 90000 --json >/dev/null 2>&1 || true
sleep 20  # let the TUI settle so it can receive the paste
orca orchestration task-update --id "$task" --status ready --json >/dev/null 2>&1 || true
orca orchestration dispatch --task "$task" --to "$h" --inject --json >/dev/null 2>&1 || true
sleep 8
orca terminal send --terminal "$h" --enter --json >/dev/null 2>&1 || true  # SUBMIT the pasted prompt

# Verify a heartbeat arrives; re-Enter up to 3x if not. Default hb back to literal "None" if the
# Python parse fails (covers M-1) so an empty $hb never masquerades as "worker alive".
for _ in 1 2 3; do
  sleep 40
  hb_raw=$(orca orchestration dispatch-show --task "$task" --json 2>&1 || true)
  hb=$(printf '%s' "$hb_raw" | python3 - <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print('None')
    sys.exit(0)
result = d.get('result', {}) if isinstance(d, dict) else {}
dispatch = result.get('dispatch', result) if isinstance(result, dict) else {}
print(dispatch.get('last_heartbeat_at') or 'None')
PY
)
  hb=${hb:-None}
  [ "$hb" != "None" ] && break
  orca terminal send --terminal "$h" --enter --json >/dev/null 2>&1 || true
done

echo "HANDLE=$h HB=$hb"
