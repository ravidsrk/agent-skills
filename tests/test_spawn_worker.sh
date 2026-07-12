#!/usr/bin/env bash
# Behavioral tests for scripts/orca-coord/spawn_worker.sh (v2 fail-closed contract).
# Uses a fake `orca` shim on PATH that serves fixture JSON and logs every call —
# no Orca runtime needed. Asserts the B1 remediation: fail-closed exits, no forced
# `task-update ready`, DAG-respecting --mark-ready, distinct exit codes 0/1/2/3.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SW="$REPO/scripts/orca-coord/spawn_worker.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_DIR="$TMP/fake"
BIN="$TMP/bin"
mkdir -p "$FAKE_DIR" "$BIN"

cat > "$BIN/orca" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_DIR/calls.log"
case "$1 $2" in
  "orchestration task-list")    cat "$FAKE_DIR/task-list.json" ;;
  "orchestration task-update")  echo '{"result":{"ok":true}}' ;;
  "orchestration dispatch")     if [ -f "$FAKE_DIR/fail-dispatch" ]; then echo '{"error":"not ready"}'; else echo '{"result":{"dispatch":{"id":"d-1"}}}'; fi ;;
  "orchestration dispatch-show") cat "$FAKE_DIR/dispatch-show.json" ;;
  "terminal create")            if [ -f "$FAKE_DIR/fail-terminal-create" ]; then echo '{"error":"boom"}'; else echo '{"result":{"terminal":{"handle":"term-1"}}}'; fi ;;
  "terminal wait")              echo '{"result":{"ok":true}}' ;;
  "terminal send")              echo '{"result":{"ok":true}}' ;;
  *)                            echo '{"result":{}}' ;;
esac
SHIM
chmod +x "$BIN/orca"

export PATH="$BIN:$PATH"
export FAKE_DIR
export SP="$TMP/sp"
mkdir -p "$SP"
export SETTLE_SECS=0 SUBMIT_SECS=0 HB_POLL_SECS=0

PASS=0; FAIL=0
check() { # check <desc> <expected_rc> <actual_rc>
  if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok: $1";
  else FAIL=$((FAIL+1)); echo "  FAIL: $1 (want rc=$2 got rc=$3)"; fi
}
assert_log() { # assert_log <desc> <grep-pattern>
  if grep -q "$2" "$FAKE_DIR/calls.log" 2>/dev/null; then PASS=$((PASS+1)); echo "  ok: $1";
  else FAIL=$((FAIL+1)); echo "  FAIL: $1 (pattern '$2' not in calls.log)"; fi
}
assert_no_log() {
  if grep -q "$2" "$FAKE_DIR/calls.log" 2>/dev/null; then FAIL=$((FAIL+1)); echo "  FAIL: $1 (pattern '$2' unexpectedly in calls.log)";
  else PASS=$((PASS+1)); echo "  ok: $1"; fi
}
reset_fake() {
  rm -f "$FAKE_DIR/calls.log" "$FAKE_DIR/fail-terminal-create" "$FAKE_DIR/fail-dispatch"
  cp "$FAKE_DIR/tl-$1.json" "$FAKE_DIR/task-list.json"
  cp "$FAKE_DIR/ds-$2.json" "$FAKE_DIR/dispatch-show.json"
}

# fixtures
cat > "$FAKE_DIR/tl-ready.json"        <<'J'
{"result":{"tasks":[{"id":"t1","status":"ready","deps":[]}]}}
J
cat > "$FAKE_DIR/tl-pending.json"      <<'J'
{"result":{"tasks":[{"id":"t1","status":"pending","deps":[]}]}}
J
cat > "$FAKE_DIR/tl-pending-unmet.json" <<'J'
{"result":{"tasks":[{"id":"t1","status":"pending","deps":["t0"]},{"id":"t0","status":"dispatched","deps":[]}]}}
J
cat > "$FAKE_DIR/tl-pending-met.json"  <<'J'
{"result":{"tasks":[{"id":"t1","status":"pending","deps":["t0"]},{"id":"t0","status":"completed","deps":[]}]}}
J
cat > "$FAKE_DIR/ds-hb.json"           <<'J'
{"result":{"dispatch":{"last_heartbeat_at":"2026-07-12T00:00:00Z"}}}
J
cat > "$FAKE_DIR/ds-none.json"         <<'J'
{"result":{"dispatch":{"last_heartbeat_at":null}}}
J

echo "S1: ready task, heartbeat -> exit 0, NO forced task-update"
reset_fake ready hb
out=$(bash "$SW" t1 "path:/tmp/wt" job1 claude 2>&1); rc=$?
check "exit 0" 0 "$rc"
case "$out" in *"HANDLE=term-1"*) PASS=$((PASS+1)); echo "  ok: prints HANDLE";; *) FAIL=$((FAIL+1)); echo "  FAIL: no HANDLE in output: $out";; esac
assert_no_log "never forces ready on a ready task" "task-update"
assert_log "submits with Enter after inject" "terminal send --terminal term-1 --enter"

echo "S2: pending without --mark-ready -> refusal 2, nothing spawned"
reset_fake pending hb
bash "$SW" t1 "path:/tmp/wt" job2 claude >/dev/null 2>&1; rc=$?
check "exit 2" 2 "$rc"
assert_no_log "no terminal created" "terminal create"

echo "S3: pending + --mark-ready + UNMET dep -> refusal 2 (DAG respected)"
reset_fake pending-unmet hb
bash "$SW" --mark-ready t1 "path:/tmp/wt" job3 claude >/dev/null 2>&1; rc=$?
check "exit 2" 2 "$rc"
assert_no_log "no task-update on unmet deps" "task-update"

echo "S4: pending + --mark-ready + deps met -> marks ready, dispatches, exit 0"
reset_fake pending-met hb
bash "$SW" --mark-ready t1 "path:/tmp/wt" job4 claude >/dev/null 2>&1; rc=$?
check "exit 0" 0 "$rc"
assert_log "task-update ready happened" "task-update --id t1 --status ready"

echo "S5: terminal create error -> fail-closed nonzero with SPAWN=FAILED"
reset_fake ready hb
touch "$FAKE_DIR/fail-terminal-create"
err=$(bash "$SW" t1 "path:/tmp/wt" job5 claude 2>&1 >/dev/null); rc=$?
check "exit 1" 1 "$rc"
case "$err" in *"SPAWN=FAILED"*) PASS=$((PASS+1)); echo "  ok: SPAWN=FAILED diagnostic";; *) FAIL=$((FAIL+1)); echo "  FAIL: no SPAWN=FAILED: $err";; esac

echo "S6: dispatched but no heartbeat -> exit 3 (respawn signal)"
reset_fake ready none
bash "$SW" t1 "path:/tmp/wt" job6 claude >/dev/null 2>&1; rc=$?
check "exit 3" 3 "$rc"

echo "S7: PROFILE=danger without ORCA_COORD_ALLOW_DANGER -> refusal 2 before any orca call"
reset_fake ready hb
rm -f "$FAKE_DIR/calls.log"
PROFILE=danger bash "$SW" t1 "path:/tmp/wt" job7 claude >/dev/null 2>&1; rc=$?
check "exit 2" 2 "$rc"
if [ -f "$FAKE_DIR/calls.log" ]; then FAIL=$((FAIL+1)); echo "  FAIL: orca was called"; else PASS=$((PASS+1)); echo "  ok: no orca calls"; fi

echo "S8: unknown PROFILE -> refusal 2"
PROFILE=yolo bash "$SW" t1 "path:/tmp/wt" job8 claude >/dev/null 2>&1; rc=$?
check "exit 2" 2 "$rc"

echo "S9: danger allowed only with explicit opt-in -> exit 0"
reset_fake ready hb
PROFILE=danger ORCA_COORD_ALLOW_DANGER=1 bash "$SW" t1 "path:/tmp/wt" job9 codex >/dev/null 2>&1; rc=$?
check "exit 0" 0 "$rc"
assert_log "codex danger flags used" "dangerously-bypass-approvals-and-sandbox"

echo
echo "spawn_worker tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
