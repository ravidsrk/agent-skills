#!/usr/bin/env bash
# spawn_worker.sh — reliable Orca worker dispatch for the ios-qa-fleet coordinator.
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
#   CLAUDE_CMD / CODEX_CMD  override the worker launch command (autonomous + max-effort flags baked in)
set -u
SP="${SP:-$(pwd)}"
task="$1"; sel="$2"; title="$3"; agent="${4:-claude}"; effort="${5:-xhigh}"

CODEX_CMD="${CODEX_CMD:-codex --dangerously-bypass-approvals-and-sandbox -c model_reasoning_effort=\"$effort\"}"
CLAUDE_CMD="${CLAUDE_CMD:-claude --dangerously-skip-permissions}"

if [ "$agent" = "codex" ]; then cmd="$CODEX_CMD"; else cmd="$CLAUDE_CMD"; fi

tj="$SP/sw-$title.json"
orca terminal create --worktree "$sel" --title "$title" --command "$cmd" --json > "$tj" 2>&1
h=$(python3 -c "import json;d=json.load(open('$tj'));r=d.get('result',d);print(r.get('terminal',{}).get('handle') or r.get('handle'))")

orca terminal wait --terminal "$h" --for tui-idle --timeout-ms 90000 --json >/dev/null 2>&1
sleep 20  # let the TUI settle so it can receive the paste
orca orchestration task-update --id "$task" --status ready --json >/dev/null 2>&1
orca orchestration dispatch --task "$task" --to "$h" --inject --json >/dev/null 2>&1
sleep 8
orca terminal send --terminal "$h" --enter --json >/dev/null 2>&1   # SUBMIT the pasted prompt (the fix)

# verify a heartbeat arrives; re-Enter up to 3x if not
hb=None
for i in 1 2 3; do
  sleep 40
  hb=$(orca orchestration dispatch-show --task "$task" --json 2>&1 | \
       python3 -c "import sys,json;d=json.load(sys.stdin).get('result',{});x=d.get('dispatch',d);print(x.get('last_heartbeat_at') or 'None')" 2>/dev/null)
  [ "$hb" != "None" ] && break
  orca terminal send --terminal "$h" --enter --json >/dev/null 2>&1
done
echo "HANDLE=$h HB=$hb"
