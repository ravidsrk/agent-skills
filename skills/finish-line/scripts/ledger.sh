#!/usr/bin/env bash
# ledger.sh — the only sanctioned way to read or change .finish/ledger.json.
#
# Mutating subcommands touch only status / attempts / evidence / notes, so the
# frozen criteria can't drift. `pass` refuses without evidence, a fresh
# verifier PASS report, a clean tamper check and a spec that asserts something.
# Nothing here waits for a human: changes to the definition of done go through
# `amend` (independent verifier approval instead of a person), and owner actions
# are re-checked automatically by `owner-check`.
#
#   ledger.sh validate              schema + rule check (exit 1 on errors)
#   ledger.sh status [--line]       summary, P0 progress, next item
#   ledger.sh next                  next item to work on (exit 1 if none)
#   ledger.sh show <ID>             print one item
#   ledger.sh specs [--passing] [--method M]   existing spec paths for in-scope items
#   ledger.sh pass <ID>             mark passing (guarded)
#   ledger.sh state                 fingerprint of the code under test (the verifier records it)
#   ledger.sh run-commands [--passing]  run in-scope verify.command items (used by verify.sh)
#   ledger.sh fail <ID> "<why>"     attempts += 1; parks as stuck at 3
#   ledger.sh stuck <ID> "<why>"    park now
#   ledger.sh owner <ID> "<owner action>" "<check cmd>"   park as needs_owner; check exits 0 once done
#   ledger.sh round2 <ID>           second and last round for a stuck item
#   ledger.sh owner-check           re-run owner checks; reopen items whose check now passes
#   ledger.sh done-check            which terminal STATUS the ledger supports: LAUNCH_READY,
#                                   READY_FOR_OWNER, or OPEN <ids> (exit 1)
#   ledger.sh reopen <ID> "<why>"   back to failing with attempts 0
#   ledger.sh regress <ID> "<why>"  passing → failing (test broke)
#   ledger.sh hash                  criteria hash
#   ledger.sh check                 criteria hash matches .finish/LEDGER.lock (exit 1 if not)
#   ledger.sh lock                  first freeze: write .finish/FREEZE + .finish/LEDGER.lock
#   ledger.sh amend "<why>"         change the definition of done from .finish/ledger.proposed.json
#   ledger.sh amend --rebaseline "<why>"   move FREEZE to HEAD (a gate change tamper.sh flags)
#   ledger.sh amend --apply <NNN>   apply an amendment the verifier approved
#   ledger.sh amend-verify <lock> <freeze> <count> <ledger>   re-check the amendment chain (used by the runner)
#   ledger.sh migrate               reopen items left in the old blocked_human status

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git jq

ROOT="$(fl_root)"
FD="$ROOT/.finish"
LEDGER="$FD/ledger.json"
cd "$ROOT" || exit 2

need_ledger() { [[ -f "$LEDGER" ]] || fl_die "no ledger at .finish/ledger.json (Phase 1 creates it)"; }

need_item() {
  [[ -n "${1:-}" ]] || fl_die "missing item ID"
  jq -e --arg id "$1" 'any(.items[]; .id == $id)' "$LEDGER" >/dev/null || fl_die "no item $1 in ledger"
}

item_field() { jq -r --arg id "$1" --arg f "$2" '.items[] | select(.id == $id) | .[$f] // empty' "$LEDGER"; }
item_verify() { jq -r --arg id "$1" --arg f "$2" '.items[] | select(.id == $id) | .verify[$f] // empty' "$LEDGER"; }

# Apply a jq update to one item. Only status/attempts/evidence/notes may change.
update_item() {
  local id="$1" filter="$2" before after tmp
  shift 2
  before="$(fl_criteria_hash "$LEDGER")"
  tmp="$(mktemp)"
  jq --arg id "$id" "$@" "(.items[] | select(.id == \$id)) |= ($filter)" "$LEDGER" > "$tmp" || { rm -f "$tmp"; fl_die "jq update failed"; }
  after="$(fl_criteria_hash "$tmp")"
  [[ "$before" == "$after" ]] || { rm -f "$tmp"; fl_die "refusing: update would change frozen criteria"; }
  mv "$tmp" "$LEDGER"
}

# shellcheck disable=SC2016  # jq variables, not shell
note_filter='.notes = ((if (.notes // "") == "" then "" else .notes + "\n" end) + $stamp + " " + $msg)'

cmd_validate() {
  local file="${1:-$LEDGER}"
  [[ -f "$file" ]] || fl_die "no ledger at ${file#"$ROOT"/}"
  local errs
  errs="$(jq -r --arg st "$FL_STATUSES" --arg ty "$FL_TYPES" --arg me "$FL_METHODS" '
    ($st | split(" ")) as $S | ($ty | split(" ")) as $T | ($me | split(" ")) as $M |
    def err(id; m): "\(id): \(m)";
    [
      (if (.product | type) != "string" or .product == "" then "ledger: product must be a non-empty string" else empty end),
      (if (.one_liner | type) != "string" or .one_liner == "" then "ledger: one_liner must be a non-empty string" else empty end),
      (if (.items | type) != "array" or (.items | length) == 0 then "ledger: items must be a non-empty array" else empty end),
      ((.items // []) | group_by(.id)[] | select(length > 1) | "\(.[0].id): duplicate id"),
      ((.items // [])[] | . as $i | ($i.id // "?") as $id |
        (if ($id | test("^[A-Z]+-[0-9]{3}$")) | not then err($id; "id must look like J-001 / F-001 / G-001") else empty end),
        (if ($T | index($i.type)) == null then err($id; "type must be one of \($T | join(", "))") else empty end),
        (if (["P0","P1","P2"] | index($i.priority)) == null then err($id; "priority must be P0, P1 or P2") else empty end),
        (if ($i.title | type) != "string" or $i.title == "" then err($id; "title required") else empty end),
        (if ($i.platforms | type) != "array" or ($i.platforms | length) == 0 then err($id; "platforms must be a non-empty array") else empty end),
        (if ($i.acceptance | type) != "array" or ($i.acceptance | length) == 0 then err($id; "acceptance must be a non-empty array")
         else ($i.acceptance[] | select((type != "string") or ((test("given"; "i") and test("when"; "i") and test("then"; "i")) | not))
               | err($id; "criterion not in Given/When/Then form: \(.)")) end),
        (if ($M | index($i.verify.method // "")) == null then err($id; "verify.method must be one of \($M | join(", "))")
         elif $i.verify.method == "command" then
           (if (($i.verify.command // "") == "") then err($id; "verify.command required for method command") else empty end)
         else
           (if (($i.verify.spec // "") | test("(^|/)finish/") | not) then err($id; "verify.spec must live under a finish/ directory (e.g. e2e/finish/\($id).spec.ts)") else empty end)
         end),
        (if ($S | index($i.status)) == null then err($id; "status must be one of \($S | join(", "))") else empty end),
        (if ($i.attempts | type) != "number" or $i.attempts < 0 then err($id; "attempts must be a number >= 0") else empty end),
        (if ($i.evidence | type) != "array" then err($id; "evidence must be an array") else empty end),
        (if ($i.notes | type) != "string" then err($id; "notes must be a string") else empty end)
      ),
      (if any((.items // [])[]; .priority == "P0" and .type == "journey") | not then "ledger: at least one P0 journey required" else empty end)
    ] | .[]' "$file" 2>&1)" || fl_die "${file#"$ROOT"/} is not valid JSON"
  if [[ -n "$errs" ]]; then
    printf '%s\n' "$errs"
    echo "LEDGER: INVALID ($(printf '%s\n' "$errs" | wc -l | tr -d ' ') errors)"
    return 1
  fi
  local first
  first="$(jq -r '.items[0].type' "$file")"
  [[ "$first" == "gate" ]] || echo "warning: item 1 should be the boot gate (fresh clone → init.sh → app runs)"
  echo "LEDGER: VALID ($(jq '.items | length' "$file") items)"
}

# shellcheck disable=SC2016  # jq variables, not shell
in_scope='(.priority | ltrimstr("P") | tonumber) <= $scope'

cmd_status() {
  local scope status
  scope="$(fl_scope_n "$FD")"
  status="$(tr -d '[:space:]' < "$FD/STATUS" 2>/dev/null || echo NEW)"
  if [[ ! -f "$LEDGER" ]]; then
    if [[ "${1:-}" == "--line" ]]; then echo "P0 0/0"; else echo "STATUS: ${status:-NEW} · no ledger yet"; fi
    return 0
  fi
  if [[ "${1:-}" == "--line" ]]; then
    jq -r '[.items[] | select(.priority == "P0")] | "P0 \(map(select(.status == "passing")) | length)/\(length)"' "$LEDGER"
    return 0
  fi
  jq -r --arg status "$status" --argjson scope "$scope" "
    [.items[] | select($in_scope)] as \$in |
    [.items[] | select(.priority == \"P0\")] as \$p0 |
    (\$in | map(select(.status == \"failing\" and .attempts < 3)) | .[0]) as \$next |
    \"\(.product) — \(.one_liner)\",
    \"STATUS: \(\$status) · SCOPE: P\(\$scope)\",
    \"In scope: \(\$in | length) — passing \(\$in | map(select(.status == \"passing\")) | length) · failing \(\$in | map(select(.status == \"failing\")) | length) · stuck \(\$in | map(select(.status == \"stuck\")) | length) · needs_owner \(\$in | map(select(.status == \"needs_owner\")) | length)\",
    \"P0 \(\$p0 | map(select(.status == \"passing\")) | length)/\(\$p0 | length)\",
    (if \$next then \"Next: \(\$next.id) — \(\$next.title) (attempts \(\$next.attempts)/3)\" else \"Next: none (see stuck / needs_owner)\" end)
  " "$LEDGER"
}

cmd_next() {
  need_ledger
  local scope out
  scope="$(fl_scope_n "$FD")"
  out="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope) | select(.status == \"failing\" and .attempts < 3)] | .[0] // empty | \"\(.id)\t\(.title)\"" "$LEDGER")"
  if [[ -z "$out" ]]; then
    echo "none"
    jq -r --argjson scope "$scope" ".items[] | select($in_scope) | select(.status == \"stuck\" or .status == \"needs_owner\") | \"  \(.status): \(.id) — \(.title)\"" "$LEDGER"
    return 1
  fi
  printf '%s\n' "$out"
}

cmd_specs() {
  need_ledger
  local scope only_passing=0 method=""
  scope="$(fl_scope_n "$FD")"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --passing) only_passing=1 ;;
      --method) shift; method="${1:-}" ;;
      *) fl_die "specs: unknown flag $1" ;;
    esac
    shift
  done
  jq -r --argjson scope "$scope" --argjson p "$only_passing" --arg m "$method" "
    .items[] | select($in_scope)
    | select(\$p == 0 or .status == \"passing\")
    | select(\$m == \"\" or .verify.method == \$m)
    | .verify.spec // empty" "$LEDGER" | while IFS= read -r spec; do
    if [[ -n "$spec" && -e "$spec" ]]; then printf '%s\n' "$spec"; fi
  done
  return 0
}

cmd_pass() {
  local id="$1" method spec dir report imgs files want n
  need_ledger; need_item "$id"
  [[ "$(item_field "$id" status)" == "failing" ]] || fl_die "$id is $(item_field "$id" status); only failing items can pass (use round2 for stuck items)"
  method="$(item_verify "$id" method)"
  spec="$(item_verify "$id" spec)"
  dir=".finish/evidence/$id"
  report="$dir/verifier/report.md"

  files="$(find "$dir" -type f ! -path "$dir/verifier/*" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$files" -gt 0 ]] || fl_die "no evidence in $dir/ — save screenshots (web/mobile) or command/test logs first"
  if [[ "$method" == "e2e-web" || "$method" == "e2e-mobile" ]]; then
    imgs="$(find "$dir" -type f ! -path "$dir/verifier/*" \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$imgs" -gt 0 ]] || fl_die "no screenshots of your own in $dir/ — a $method item needs visual evidence (the verifier's don't count)"
  fi

  [[ -f "$report" ]] || fl_die "no verifier report at $report — spawn finish-verifier with only the item ID"
  grep -Eq '^VERDICT: *PASS' "$report" || fl_die "verifier report does not say VERDICT: PASS"
  want="$(sed -n 's/^STATE: *\([0-9a-f][0-9a-f]*\).*/\1/p' "$report" | head -1)"
  [[ -n "$want" ]] || fl_die "verifier report has no STATE line — the verifier must end by recording ./.finish/bin/ledger.sh state"
  [[ "$want" == "$(fl_code_state)" ]] || fl_die "the code changed after the verifier checked it (STATE mismatch) — re-verify, then pass before committing"

  if [[ -n "$spec" ]]; then
    [[ -f "$spec" ]] || fl_die "spec $spec does not exist"
    n="$(fl_assert_count "$spec")"
    [[ "${n:-0}" -gt 0 ]] || fl_die "spec $spec contains no assertions"
  fi

  "$HERE/tamper.sh" >/dev/null 2>&1 || fl_die "tamper check fails — run tamper.sh and fix before passing anything"

  local ev
  ev="$(find "$dir" -type f 2>/dev/null | sort | jq -R . | jq -s .)"
  update_item "$id" ".status = \"passing\" | .evidence = \$ev | $note_filter" \
    --argjson ev "$ev" --arg stamp "$(fl_now)" --arg msg "passed (verifier PASS)"

  if [[ -n "$spec" ]]; then
    local rat="$FD/ratchet.json" tmp
    [[ -f "$rat" ]] || echo '{}' > "$rat"
    tmp="$(mktemp)"
    jq --arg id "$id" --arg spec "$spec" --argjson n "$n" --arg at "$(fl_now)" \
      '.[$id] = {spec: $spec, assertions: ([$n, (.[$id].assertions // 0)] | max), recorded_at: $at}' "$rat" > "$tmp" && mv "$tmp" "$rat"
  fi

  local idx="$FD/evidence/INDEX.md" title
  title="$(item_field "$id" title)"
  if [[ ! -f "$idx" ]]; then
    mkdir -p "$FD/evidence"
    printf '# Evidence index\n\n| Item | Title | Passed (UTC) | Spec | Evidence files | Verifier |\n|---|---|---|---|---|---|\n' > "$idx"
  fi
  printf '| %s | %s | %s | %s | %s | %s |\n' "$id" "$title" "$(fl_now)" "${spec:-$(item_verify "$id" command)}" "$files" "$report" >> "$idx"
  echo "$id → passing"
}

cmd_fail() {
  local id="$1" msg="${2:-}" a
  need_ledger; need_item "$id"
  [[ -n "$msg" ]] || fl_die "fail needs a one-line reason"
  retire_report "$id"
  update_item "$id" ".attempts += 1 | (if .attempts >= 3 then .status = \"stuck\" else .status = \"failing\" end) | $note_filter" \
    --arg stamp "$(fl_now)" --arg msg "attempt failed: $msg"
  a="$(item_field "$id" attempts)"
  if [[ "$(item_field "$id" status)" == "stuck" ]]; then
    echo "$id → stuck after $a attempts. Note hypothesis / tried / next idea in PROGRESS.md and take the next item."
  else
    echo "$id → failing (attempt $a/3)"
  fi
}

# A verdict belongs to one attempt: retire the report whenever the item leaves passing or is retried.
retire_report() {
  local r=".finish/evidence/$1/verifier/report.md"
  if [[ -f "$r" ]]; then mv "$r" ".finish/evidence/$1/verifier/report.stale-$(date +%Y%m%d-%H%M%S).md"; fi
}

set_status() {
  local id="$1" st="$2" msg="$3" extra="${4:-}"
  need_ledger; need_item "$id"
  [[ -n "$msg" ]] || fl_die "a one-line reason is required"
  retire_report "$id"
  update_item "$id" ".status = \"$st\"$extra | $note_filter" --arg stamp "$(fl_now)" --arg msg "$msg"
  echo "$id → $st"
}

cmd_round2() {
  local id="$1"
  need_ledger; need_item "$id"
  [[ "$(item_field "$id" status)" == "stuck" ]] || fl_die "$id is not stuck"
  if item_field "$id" notes | grep -q 'round 2'; then
    fl_die "$id already had round 2 — decide now: ledger.sh amend (split or re-scope, verifier-approved) or ledger.sh owner $id \"<action>\" \"<check>\""
  fi
  set_status "$id" failing "round 2: re-read code and docs from scratch" " | .attempts = 0"
}

cmd_run_commands() { # run in-scope command items; --passing = only items already passing
  need_ledger
  local scope only_passing=0 n=0 rec id cmd
  [[ "${1:-}" == "--passing" ]] && only_passing=1
  scope="$(fl_scope_n "$FD")"
  # One compact JSON record per item, so multi-line commands stay intact.
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    id="$(printf '%s' "$rec" | jq -r '.[0]')"
    cmd="$(printf '%s' "$rec" | jq -r '.[1]')"
    n=$((n + 1))
    mkdir -p ".finish/evidence/$id"
    echo "── $id: $cmd"
    if ! bash -c "$cmd" > ".finish/evidence/$id/command.log" 2>&1; then
      tail -20 ".finish/evidence/$id/command.log"
      echo "COMMAND ITEM FAILED: $id (full log: .finish/evidence/$id/command.log)"
      return 1
    fi
  done < <(jq -c --argjson scope "$scope" --argjson p "$only_passing" "
    .items[] | select($in_scope) | select(.verify.method == \"command\")
    | select(\$p == 0 or .status == \"passing\") | [.id, .verify.command]" "$LEDGER")
  echo "$n command item(s) passed"
}

cmd_lock() {
  need_ledger
  if [[ -f "$FD/FREEZE" && "${1:-}" != "--refreeze" ]]; then
    fl_die "ledger already frozen at $(cat "$FD/FREEZE"). Change the definition of done with: ledger.sh amend \"<why>\""
  fi
  cmd_validate >/dev/null || fl_die "ledger invalid — run ledger.sh validate"
  if ! git ls-files --error-unmatch .finish/ledger.json >/dev/null 2>&1 || ! git diff --quiet HEAD -- .finish/ledger.json 2>/dev/null; then
    fl_die "commit .finish/ledger.json first; FREEZE must point at the commit that contains it"
  fi
  git rev-parse HEAD > "$FD/FREEZE"
  fl_criteria_hash "$LEDGER" > "$FD/LEDGER.lock"
  echo "frozen at $(cat "$FD/FREEZE") · criteria $(cat "$FD/LEDGER.lock")"
  echo "now: git add .finish/FREEZE .finish/LEDGER.lock && git commit -m \"chore(finish): freeze ledger\""
}

cmd_check() {
  need_ledger
  [[ -f "$FD/LEDGER.lock" ]] || { echo "not frozen yet"; return 0; }
  if [[ "$(fl_criteria_hash "$LEDGER")" == "$(tr -d '[:space:]' < "$FD/LEDGER.lock")" ]]; then
    echo "LEDGER LOCK: OK"
  else
    echo "LEDGER LOCK: MISMATCH — frozen criteria were hand-edited. Restore the last committed .finish/ledger.json and change criteria only with ledger.sh amend"
    return 1
  fi
}


# ── Owner actions ─────────────────────────────────────────────────────────────
# Things only the product owner can do (a credential, an account, DNS, a store
# listing). The item is parked as needs_owner with an exact action and a shell
# check that exits 0 once it's done; owner-check reopens it automatically, so
# nobody has to mark anything as resolved.

OWNER="$FD/owner.json"

owner_md() { # regenerate .finish/OWNER_ACTIONS.md from owner.json
  {
    echo "# Owner actions"
    echo
    echo "Everything else is handled autonomously. Do these, then rerun finish.sh; each item reopens by itself once its check passes."
    echo
    if [[ -s "$OWNER" ]] && [[ "$(jq 'length' "$OWNER")" -gt 0 ]]; then
      jq -r 'to_entries[] | "- **\(.key)** — \(.value.action)\n  - detected by: `\(.value.check)`\n  - waiting since \(.value.since)"' "$OWNER"
    else
      echo "None."
    fi
  } > "$FD/OWNER_ACTIONS.md"
}

cmd_owner() {
  local id="$1" action="${2:-}" check="${3:-}" tmp
  need_ledger; need_item "$id"
  [[ -n "$action" ]] || fl_die "owner needs the exact action, e.g. \"Add STRIPE_SECRET_KEY (test mode) to .env.local\""
  [[ -n "$check" ]] || fl_die "owner needs a check command that exits 0 once the action is done, e.g. 'grep -q ^STRIPE_SECRET_KEY= .env.local'"
  set_status "$id" needs_owner "owner action: $action"
  [[ -f "$OWNER" ]] || echo '{}' > "$OWNER"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg a "$action" --arg c "$check" --arg t "$(fl_now)" '.[$id] = {action: $a, check: $c, since: $t}' "$OWNER" > "$tmp" && mv "$tmp" "$OWNER"
  owner_md
}

# Run a shell check with a time limit (portable: no coreutils timeout on macOS). 124 = timed out.
# The check gets its own process group, so a timeout stops everything it started
# (test workers, browsers), not just its shell.
run_limited() {
  local secs="$1" cmd="$2" pid t=0
  set -m
  bash -c "$cmd" >/dev/null 2>&1 &
  pid=$!
  set +m
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $t -ge $((secs * 10)) ]]; then
      kill -TERM -- "-$pid" 2>/dev/null; sleep 0.5; kill -KILL -- "-$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1; t=$((t + 1))
  done
  wait "$pid" 2>/dev/null
}

cmd_owner_check() {
  need_ledger
  [[ -f "$OWNER" ]] || { owner_md; echo "owner-check: nothing waiting"; return 0; }
  local reopened="" rec id check action tmp
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    id="$(printf '%s' "$rec" | jq -r '.[0]')"; check="$(printf '%s' "$rec" | jq -r '.[1]')"; action="$(printf '%s' "$rec" | jq -r '.[2]')"
    if [[ "$(item_field "$id" status)" != "needs_owner" ]]; then
      tmp="$(mktemp)"; jq --arg id "$id" 'del(.[$id])' "$OWNER" > "$tmp" && mv "$tmp" "$OWNER"; continue
    fi
    if run_limited "${FINISH_OWNER_CHECK_TIMEOUT:-60}" "$check"; then
      set_status "$id" failing "owner action detected: $action" " | .attempts = 0" >/dev/null
      tmp="$(mktemp)"; jq --arg id "$id" 'del(.[$id])' "$OWNER" > "$tmp" && mv "$tmp" "$OWNER"
      reopened="$reopened $id"
    fi
  done < <(jq -c 'to_entries[] | [.key, .value.check, .value.action]' "$OWNER")
  owner_md
  if [[ -n "$reopened" ]]; then echo "owner-check: reopened$reopened"; else echo "owner-check: still waiting on $(jq 'length' "$OWNER")"; fi
}

# Products started before needs_owner existed: reopen their blocked_human items so the
# agent re-evaluates them and, if still needed, records a proper owner action with a check.
cmd_migrate() {
  need_ledger
  local ids
  ids="$(jq -r '.items[] | select(.status == "blocked_human") | .id' "$LEDGER")"
  [[ -n "$ids" ]] || { echo "migrate: nothing to do"; return 0; }
  for id in $ids; do
    set_status "$id" failing "migrated from blocked_human: re-evaluate; if it still needs the owner, record ledger.sh owner with a check" " | .attempts = 0" >/dev/null
  done
  echo "migrate: reopened $(printf '%s' "$ids" | tr '\n' ' ')"
}

cmd_done_check() {
  need_ledger
  local scope out
  scope="$(fl_scope_n "$FD")"
  out="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope)] as \$in |
    (\$in | map(select(.status != \"passing\" and .status != \"needs_owner\")) | map(.id)) as \$open |
    if (\$open | length) > 0 then \"OPEN \(\$open | join(\" \"))\"
    elif any(\$in[]; .status == \"needs_owner\") then \"READY_FOR_OWNER\" else \"LAUNCH_READY\" end" "$LEDGER")"
  echo "$out"
  [[ "$out" != OPEN* ]]
}

# ── Amendments ────────────────────────────────────────────────────────────────
# The definition of done can change without a human. Additions (new items, new
# criteria, higher priority, more platforms) apply at once. Anything that removes,
# rewords or demotes — and any FREEZE rebaseline — needs a finish-verifier review
# that says VERDICT: APPROVE for that exact request, and is capped at
# FINISH_MAX_AMENDMENTS (default 5) per product. Every change is logged in
# .finish/amendments.jsonl with before/after hashes, so the runner can audit it.

AMD_DIR="$FD/amendments"
AMD_LOG="$FD/amendments.jsonl"
PROPOSED="$FD/ledger.proposed.json"

amd_next_n() { # next number across applied (log) and pending (request files) amendments
  local n m
  n="$(cat "$AMD_LOG" 2>/dev/null | wc -l | tr -d ' ')"
  m="$(find "$AMD_DIR" -name '[0-9][0-9][0-9].request.md' 2>/dev/null | sed 's|.*/||; s|\.request\.md$||; s/^0*//' | sort -n | tail -1)"
  [[ -n "$m" && "$m" -gt "$n" ]] && n="$m"
  printf '%03d' $((n + 1))
}
amd_weakening_count() { if [[ -s "$AMD_LOG" ]]; then jq -s '[.[] | select(.class == "weakening")] | length' "$AMD_LOG"; else echo 0; fi; }

# shellcheck disable=SC2016  # jq program
AMD_VIEW='def view: del(.status, .attempts, .evidence, .notes); def pn: .priority | ltrimstr("P") | tonumber;'

amd_class() { # amd_class <old ledger> <new ledger> → strengthening | weakening
  jq -rn --slurpfile o "$1" --slurpfile n "$2" "$AMD_VIEW"'
    ($o[0]) as $o | ($n[0]) as $n |
    ($n.items | map({key: .id, value: view}) | from_entries) as $N |
    if $o.product == $n.product and $o.one_liner == $n.one_liner and
       all($o.items[] | view; . as $oi | $N[$oi.id] as $ni |
         $ni != null and $ni.type == $oi.type and ($ni | pn) <= ($oi | pn)
         and (($oi.platforms - $ni.platforms) | length) == 0
         and (($oi.acceptance - $ni.acceptance) | length) == 0
         and $ni.verify == $oi.verify and $ni.title == $oi.title and ($ni.source // "") == ($oi.source // ""))
    then "strengthening" else "weakening" end'
}

amd_diff() { # human-readable change list
  jq -rn --slurpfile o "$1" --slurpfile n "$2" "$AMD_VIEW"'
    ($o[0]) as $o | ($n[0]) as $n |
    ($o.items | map({key: .id, value: view}) | from_entries) as $O |
    ($n.items | map({key: .id, value: view}) | from_entries) as $N |
    (if $o.one_liner != $n.one_liner then "- one_liner: \"\($o.one_liner)\" → \"\($n.one_liner)\"" else empty end),
    ($O | keys[] | select($N[.] == null) | "- REMOVED \(.) — \($O[.].title)"),
    ($N | keys[] | select($O[.] == null) | "- ADDED \(.) (\($N[.].priority)) — \($N[.].title)"),
    ($O | keys[] | select($N[.] != null and $N[.] != $O[.]) | . as $id | $O[$id] as $a | $N[$id] as $b |
      "- CHANGED \($id):",
      (if $a.priority != $b.priority then "  - priority \($a.priority) → \($b.priority)" else empty end),
      (($a.acceptance - $b.acceptance)[] | "  - criterion removed: \(.)"),
      (($b.acceptance - $a.acceptance)[] | "  - criterion added: \(.)"),
      (if $a.verify != $b.verify then "  - verify \($a.verify | tojson) → \($b.verify | tojson)" else empty end),
      (if $a.platforms != $b.platforms then "  - platforms \($a.platforms | tojson) → \($b.platforms | tojson)" else empty end),
      (if $a.title != $b.title then "  - title \"\($a.title)\" → \"\($b.title)\"" else empty end))'
}

amd_log() { # amd_log n kind class reason lock_before lock_after freeze_before freeze_after request review
  jq -cn --arg n "$1" --arg kind "$2" --arg class "$3" --arg reason "$4" --arg lb "$5" --arg la "$6" \
    --arg fb "$7" --arg fa "$8" --arg req "$9" --arg rev "${10}" --arg at "$(fl_now)" \
    '{n: $n, at: $at, kind: $kind, class: $class, reason: $reason, lock_before: $lb, lock_after: $la,
      freeze_before: $fb, freeze_after: $fa, request: $req, review: (if $rev == "" then null else $rev end)}' >> "$AMD_LOG"
}

amd_apply_ledger() { # amd_apply_ledger <n>: merge mutable fields from the current ledger into the proposed one, install it, snapshot it
  local tmp
  tmp="$(mktemp)"
  jq --slurpfile cur "$LEDGER" "$AMD_VIEW"'
    ($cur[0].items | map({key: .id, value: .}) | from_entries) as $C |
    .items |= map(. as $p | $C[$p.id] as $c |
      if $c != null and ($c | view) == ($p | view)
      then $p + {status: $c.status, attempts: $c.attempts, evidence: $c.evidence, notes: $c.notes}
      else $p + {status: "failing", attempts: 0, evidence: [], notes: (($c.notes // "") + (if $c then "\n" else "" end) + "amended: re-verify")}
      end)' "$PROPOSED" > "$tmp" || { rm -f "$tmp"; fl_die "could not merge the proposed ledger"; }
  mv "$tmp" "$LEDGER"
  rm -f "$PROPOSED"
  cp "$LEDGER" "$AMD_DIR/$1.ledger.json"
}

cmd_amend() {
  need_ledger
  [[ -f "$FD/FREEZE" ]] || fl_die "not frozen yet — edit .finish/ledger.json directly and run ledger.sh lock"
  local mode=ledger reason="" applyn="" n req class lock_before freeze_before
  case "${1:-}" in
    --rebaseline) mode=rebaseline; reason="${2:-}" ;;
    --apply) mode=apply; applyn="${2:-}" ;;
    *) reason="${1:-}" ;;
  esac
  lock_before="$(tr -d '[:space:]' < "$FD/LEDGER.lock")"
  freeze_before="$(tr -d '[:space:]' < "$FD/FREEZE")"
  mkdir -p "$AMD_DIR"

  if [[ "$mode" == "apply" ]]; then
    [[ -n "$applyn" && -f "$AMD_DIR/$applyn.request.md" ]] || fl_die "no request $AMD_DIR/$applyn.request.md"
    if jq -e --arg n "$applyn" 'select(.n == $n)' "$AMD_LOG" >/dev/null 2>&1; then fl_die "amendment $applyn was already applied"; fi
    local review="$AMD_DIR/$applyn.review.md" reqhash kind
    reqhash="$(fl_sha < "$AMD_DIR/$applyn.request.md")"
    [[ -f "$review" ]] || fl_die "no review at $review — spawn finish-verifier in amendment mode with: $AMD_DIR/$applyn.request.md"
    grep -Eq '^VERDICT: *APPROVE' "$review" || fl_die "the verifier did not approve amendment $applyn — take another route (owner action, or keep working the item)"
    grep -Eq "^REQUEST: *$reqhash" "$review" || fl_die "review $applyn is for a different request (REQUEST hash mismatch)"
    [[ "$(amd_weakening_count)" -lt "${FINISH_MAX_AMENDMENTS:-5}" ]] || fl_die "amendment cap reached (${FINISH_MAX_AMENDMENTS:-5}); park the item with ledger.sh owner instead"
    kind="$(sed -n 's/^KIND: *//p' "$AMD_DIR/$applyn.request.md" | head -1)"
    reason="$(sed -n 's/^REASON: *//p' "$AMD_DIR/$applyn.request.md" | head -1)"
    if [[ "$kind" == "rebaseline" ]]; then
      local want_head; want_head="$(sed -n 's/^HEAD: *//p' "$AMD_DIR/$applyn.request.md" | head -1)"
      [[ "$(git rev-parse HEAD)" == "$want_head" ]] || fl_die "HEAD moved since the rebaseline request; propose it again"
      [[ "$(sed -n 's/^FREEZE: *//p' "$AMD_DIR/$applyn.request.md" | head -1)" == "$freeze_before" ]] || fl_die "FREEZE moved since request $applyn; propose it again"
      git rev-parse HEAD > "$FD/FREEZE"
      amd_log "$applyn" rebaseline weakening "$reason" "$lock_before" "$lock_before" "$freeze_before" "$(cat "$FD/FREEZE")" "$AMD_DIR/$applyn.request.md" "$review"
      echo "amendment $applyn applied: FREEZE → $(cat "$FD/FREEZE")"
    else
      local want_after; want_after="$(sed -n 's/^AFTER: *//p' "$AMD_DIR/$applyn.request.md" | head -1)"
      [[ "$(sed -n 's/^BEFORE: *//p' "$AMD_DIR/$applyn.request.md" | head -1)" == "$lock_before" ]] \
        || fl_die "the definition of done changed since request $applyn was reviewed; propose it again"
      [[ -f "$PROPOSED" && "$(fl_criteria_hash "$PROPOSED")" == "$want_after" ]] || fl_die ".finish/ledger.proposed.json no longer matches request $applyn"
      amd_apply_ledger "$applyn"
      fl_criteria_hash "$LEDGER" > "$FD/LEDGER.lock"
      amd_log "$applyn" ledger weakening "$reason" "$lock_before" "$(cat "$FD/LEDGER.lock")" "$freeze_before" "$freeze_before" "$AMD_DIR/$applyn.request.md" "$review"
      echo "amendment $applyn applied: criteria $(cat "$FD/LEDGER.lock")"
    fi
    echo "now commit: git add .finish && git commit -m \"chore(finish): amendment $applyn — $reason\""
    return 0
  fi

  [[ -n "$reason" ]] || fl_die "amend needs a one-line reason"
  n="$(amd_next_n)"
  req="$AMD_DIR/$n.request.md"

  if [[ "$mode" == "rebaseline" ]]; then
    [[ -z "$(git status --porcelain -- . ':(exclude).finish/amendments' ':(exclude).finish/logs' 2>/dev/null)" ]] \
      || fl_die "commit the change first; a rebaseline freezes HEAD as it is"
    git diff --quiet "$freeze_before" HEAD -- .finish/bin 2>/dev/null \
      || fl_die "refusing: .finish/bin changed since the freeze; vendored scripts can't be rebaselined"
    {
      echo "# Amendment $n — rebaseline"
      echo; echo "KIND: rebaseline"; echo "REASON: $reason"; echo "HEAD: $(git rev-parse HEAD)"; echo "FREEZE: $freeze_before"
      echo; echo "## What tamper.sh flags now"; echo '```'; "$HERE/tamper.sh" 2>&1 | head -40; echo '```'
      echo; echo "## Changes since the freeze in flagged areas"; echo '```'
      git diff --stat "$freeze_before" HEAD 2>/dev/null | tail -40; echo '```'
    } > "$req"
    echo "amendment $n needs review (rebaseline). Spawn finish-verifier in amendment mode with: $req"
    echo "then: ledger.sh amend --apply $n"
    return 3
  fi

  [[ -f "$PROPOSED" ]] || fl_die "write the full proposed ledger to .finish/ledger.proposed.json first"
  cmd_validate "$PROPOSED" >/dev/null || { cmd_validate "$PROPOSED"; fl_die "proposed ledger is invalid"; }
  [[ "$(fl_criteria_hash "$PROPOSED")" != "$lock_before" ]] || fl_die "the proposed ledger changes no criteria"
  class="$(amd_class "$LEDGER" "$PROPOSED")"
  {
    echo "# Amendment $n — $class"
    echo; echo "KIND: ledger"; echo "CLASS: $class"; echo "REASON: $reason"
    echo "BEFORE: $lock_before"; echo "AFTER: $(fl_criteria_hash "$PROPOSED")"
    echo; echo "## Changes"; amd_diff "$LEDGER" "$PROPOSED"
  } > "$req"
  if [[ "$class" == "strengthening" ]]; then
    amd_apply_ledger "$n"
    fl_criteria_hash "$LEDGER" > "$FD/LEDGER.lock"
    amd_log "$n" ledger strengthening "$reason" "$lock_before" "$(cat "$FD/LEDGER.lock")" "$freeze_before" "$freeze_before" "$req" ""
    echo "amendment $n applied (strengthening, no review needed): criteria $(cat "$FD/LEDGER.lock")"
    echo "now commit: git add .finish && git commit -m \"chore(finish): amendment $n — $reason\""
    return 0
  fi
  echo "amendment $n weakens the definition of done and needs review. Spawn finish-verifier in amendment mode with: $req"
  echo "then: ledger.sh amend --apply $n   ($(amd_weakening_count)/${FINISH_MAX_AMENDMENTS:-5} weakening amendments used)"
  return 3
}

# amend-verify <old lock> <old freeze> <old log line count> <ledger at session start>:
# the lock/FREEZE moved only through logged amendments. Nothing in the log is
# trusted: each ledger step is recomputed from its snapshot, and every step that
# isn't purely additive — and every FREEZE move — needs an APPROVE review bound
# to its request.
cmd_amend_verify() {
  local old_lock="$1" old_freeze="$2" old_n="$3" prev="$4" lock freeze total
  lock="$(tr -d '[:space:]' < "$FD/LEDGER.lock" 2>/dev/null)"; freeze="$(tr -d '[:space:]' < "$FD/FREEZE" 2>/dev/null)"
  total="$(cat "$AMD_LOG" 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$lock" == "$old_lock" && "$freeze" == "$old_freeze" ]]; then echo "AMENDMENTS: none"; return 0; fi
  [[ "$total" -gt "$old_n" ]] || { echo "AMENDMENTS: lock or FREEZE changed with no logged amendment"; return 1; }
  [[ -f "$prev" && "$(fl_criteria_hash "$prev")" == "$old_lock" ]] || { echo "AMENDMENTS: no trusted snapshot of the starting ledger"; return 1; }
  local cl="$old_lock" cf="$old_freeze" rec n lb la fb fa logged class req rev snap weak=0
  weak=0; [[ "$old_n" -gt 0 ]] && weak="$(head -n "$old_n" "$AMD_LOG" | jq -s '[.[] | select(.class == "weakening")] | length')"
  while IFS= read -r rec; do
    n="$(printf '%s' "$rec" | jq -r .n)"
    lb="$(printf '%s' "$rec" | jq -r .lock_before)"; la="$(printf '%s' "$rec" | jq -r .lock_after)"
    fb="$(printf '%s' "$rec" | jq -r .freeze_before)"; fa="$(printf '%s' "$rec" | jq -r .freeze_after)"
    logged="$(printf '%s' "$rec" | jq -r .class)"; req="$(printf '%s' "$rec" | jq -r '.request // ""')"; rev="$(printf '%s' "$rec" | jq -r '.review // ""')"
    [[ "$lb" == "$cl" && "$fb" == "$cf" ]] || { echo "AMENDMENTS: broken chain at $n"; return 1; }
    if [[ "$fa" != "$fb" ]]; then
      [[ "$la" == "$lb" ]] || { echo "AMENDMENTS: $n moves FREEZE and the criteria at once"; return 1; }
      class=weakening
    else
      snap="$AMD_DIR/$n.ledger.json"
      [[ -f "$snap" && "$(fl_criteria_hash "$snap")" == "$la" ]] || { echo "AMENDMENTS: $n has no matching ledger snapshot"; return 1; }
      class="$(amd_class "$prev" "$snap")"
      prev="$snap"
    fi
    [[ "$logged" == "$class" ]] || { echo "AMENDMENTS: $n is logged as $logged but is $class"; return 1; }
    if [[ "$class" == "weakening" ]]; then
      weak=$((weak + 1))
      [[ -f "$req" && -f "$rev" ]] || { echo "AMENDMENTS: $n has no request/review on disk"; return 1; }
      if ! grep -Eq '^VERDICT: *APPROVE' "$rev" || ! grep -Eq "^REQUEST: *$(fl_sha < "$req")" "$rev"; then
        echo "AMENDMENTS: $n is not approved for this exact request"; return 1
      fi
    fi
    cl="$la"; cf="$fa"
  done < <(tail -n "$((total - old_n))" "$AMD_LOG")
  [[ "$cl" == "$lock" && "$cf" == "$freeze" ]] || { echo "AMENDMENTS: current lock/FREEZE don't match the last amendment"; return 1; }
  [[ "$weak" -le "${FINISH_MAX_AMENDMENTS:-5}" ]] || { echo "AMENDMENTS: over the cap"; return 1; }
  echo "AMENDMENTS: $((total - old_n)) verified"
}

sub="${1:-}"; shift || true
case "$sub" in
  validate) cmd_validate "${1:-}" ;;
  status) cmd_status "${1:-}" ;;
  next) cmd_next ;;
  show) need_ledger; need_item "${1:-}"; jq --arg id "$1" '.items[] | select(.id == $id)' "$LEDGER" ;;
  specs) cmd_specs "$@" ;;
  pass) cmd_pass "${1:-}" ;;
  fail) cmd_fail "${1:-}" "${2:-}" ;;
  stuck) set_status "${1:-}" stuck "${2:-}" ;;
  owner) cmd_owner "${1:-}" "${2:-}" "${3:-}" ;;
  block) cmd_owner "${1:-}" "${2:-}" "${3:-}" ;;
  owner-check) cmd_owner_check ;;
  done-check) cmd_done_check ;;
  amend) cmd_amend "$@" ;;
  amend-verify) cmd_amend_verify "${1:-}" "${2:-}" "${3:-0}" "${4:-}" ;;
  migrate) cmd_migrate ;;
  reopen) set_status "${1:-}" failing "${2:-}" " | .attempts = 0" ;;
  regress) [[ -n "${2:-}" ]] || fl_die "regress needs a one-line reason"; set_status "${1:-}" failing "regressed: $2" ;;
  round2) cmd_round2 "${1:-}" ;;
  hash) need_ledger; fl_criteria_hash "$LEDGER" ;;
  state) fl_code_state ;;
  run-commands) cmd_run_commands "${1:-}" ;;
  check) cmd_check ;;
  lock) cmd_lock "${1:-}" ;;
  ""|-h|--help|help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}" ;;
  *) fl_die "unknown subcommand: $sub (try --help)" ;;
esac
