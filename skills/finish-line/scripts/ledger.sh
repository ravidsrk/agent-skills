#!/usr/bin/env bash
# ledger.sh — the only sanctioned way to read or change .finish/ledger.json.
#
# Mutating subcommands touch only status / attempts / evidence / notes, so the
# frozen criteria can't drift. `pass` refuses without evidence, a fresh
# verifier PASS report, a clean tamper check and a spec that asserts something.
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
#   ledger.sh block <ID> "<why>"    needs a human (blocked_human)
#   ledger.sh round2 <ID>           second and last round for a stuck item
#   ledger.sh reopen <ID> "<why>"   back to failing with attempts 0 (resolved blocker)
#   ledger.sh regress <ID> "<why>"  passing → failing (test broke)
#   ledger.sh hash                  criteria hash
#   ledger.sh check                 criteria hash matches .finish/LEDGER.lock (exit 1 if not)
#   ledger.sh lock [--refreeze]     write .finish/FREEZE + .finish/LEDGER.lock (first freeze; --refreeze is human-only)

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
  need_ledger
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
    ] | .[]' "$LEDGER" 2>&1)" || fl_die "ledger.json is not valid JSON"
  if [[ -n "$errs" ]]; then
    printf '%s\n' "$errs"
    echo "LEDGER: INVALID ($(printf '%s\n' "$errs" | wc -l | tr -d ' ') errors)"
    return 1
  fi
  local first
  first="$(jq -r '.items[0].type' "$LEDGER")"
  [[ "$first" == "gate" ]] || echo "warning: item 1 should be the boot gate (fresh clone → init.sh → app runs)"
  echo "LEDGER: VALID ($(jq '.items | length' "$LEDGER") items)"
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
    \"In scope: \(\$in | length) — passing \(\$in | map(select(.status == \"passing\")) | length) · failing \(\$in | map(select(.status == \"failing\")) | length) · stuck \(\$in | map(select(.status == \"stuck\")) | length) · blocked_human \(\$in | map(select(.status == \"blocked_human\")) | length)\",
    \"P0 \(\$p0 | map(select(.status == \"passing\")) | length)/\(\$p0 | length)\",
    (if \$next then \"Next: \(\$next.id) — \(\$next.title) (attempts \(\$next.attempts)/3)\" else \"Next: none (see stuck / blocked_human)\" end)
  " "$LEDGER"
}

cmd_next() {
  need_ledger
  local scope out
  scope="$(fl_scope_n "$FD")"
  out="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope) | select(.status == \"failing\" and .attempts < 3)] | .[0] // empty | \"\(.id)\t\(.title)\"" "$LEDGER")"
  if [[ -z "$out" ]]; then
    echo "none"
    jq -r --argjson scope "$scope" ".items[] | select($in_scope) | select(.status == \"stuck\" or .status == \"blocked_human\") | \"  \(.status): \(.id) — \(.title)\"" "$LEDGER"
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
    echo "$id → stuck after $a attempts. Write a BLOCKERS.md entry (hypothesis, tried, next idea) and take the next item."
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
    fl_die "$id already had round 2 — use: ledger.sh block $id \"<what a human must do>\""
  fi
  set_status "$id" failing "round 2: re-read code and docs from scratch" " | .attempts = 0"
}

cmd_run_commands() { # run in-scope command items; --passing = only items already passing
  need_ledger
  local scope only_passing=0 n=0 id cmd
  [[ "${1:-}" == "--passing" ]] && only_passing=1
  scope="$(fl_scope_n "$FD")"
  while IFS=$'\t' read -r id cmd; do
    [[ -n "$id" ]] || continue
    n=$((n + 1))
    mkdir -p ".finish/evidence/$id"
    echo "── $id: $cmd"
    if ! bash -c "$cmd" > ".finish/evidence/$id/command.log" 2>&1; then
      tail -20 ".finish/evidence/$id/command.log"
      echo "COMMAND ITEM FAILED: $id (full log: .finish/evidence/$id/command.log)"
      return 1
    fi
  done < <(jq -r --argjson scope "$scope" --argjson p "$only_passing" "
    .items[] | select($in_scope) | select(.verify.method == \"command\")
    | select(\$p == 0 or .status == \"passing\") | \"\(.id)\t\(.verify.command)\"" "$LEDGER")
  echo "$n command item(s) passed"
}

cmd_lock() {
  need_ledger
  if [[ -f "$FD/FREEZE" && "${1:-}" != "--refreeze" ]]; then
    fl_die "ledger already frozen at $(cat "$FD/FREEZE"). Re-freezing is a human decision: ledger.sh lock --refreeze"
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
    echo "LEDGER LOCK: MISMATCH — frozen criteria were edited. Restore with: git checkout \$(cat .finish/FREEZE) -- .finish/ledger.json (then re-apply status changes via ledger.sh)"
    return 1
  fi
}

sub="${1:-}"; shift || true
case "$sub" in
  validate) cmd_validate ;;
  status) cmd_status "${1:-}" ;;
  next) cmd_next ;;
  show) need_ledger; need_item "${1:-}"; jq --arg id "$1" '.items[] | select(.id == $id)' "$LEDGER" ;;
  specs) cmd_specs "$@" ;;
  pass) cmd_pass "${1:-}" ;;
  fail) cmd_fail "${1:-}" "${2:-}" ;;
  stuck) set_status "${1:-}" stuck "${2:-}" ;;
  block) set_status "${1:-}" blocked_human "${2:-}" ;;
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
