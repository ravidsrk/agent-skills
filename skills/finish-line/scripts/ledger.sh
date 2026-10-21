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
#   ledger.sh validate              schema + rule check (exit 1 on errors); with a brief, every item
#                                   but a defect cites the brief claims it comes from
#   ledger.sh status [--line]       summary, P0 progress, next item
#   ledger.sh next                  next failing item to work on (exit 1 if none)
#   ledger.sh next --stuck          the stuck item with the fewest research rounds (exit 1 if none)
#   ledger.sh open                  every in-scope item that isn't passing, with its status and rounds
#   ledger.sh show <ID>             print one item
#   ledger.sh specs [--passing] [--method M]   existing spec paths for in-scope items
#   ledger.sh pass <ID>             mark passing (guarded)
#   ledger.sh state                 fingerprint of the code under test (the verifier records it)
#   ledger.sh run-commands [--passing]  run in-scope verify.command items (used by verify.sh)
#   ledger.sh fail <ID> "<why>"     attempts += 1; pauses as stuck at 3 (never abandoned)
#   ledger.sh stuck <ID> "<why>"    pause now
#   ledger.sh round <ID>            next research round for a stuck item: back to failing, attempts 0.
#                                   Unlimited; each round escalates (protocol §5.1). round2 is an alias.
#   ledger.sh issue --title "<t>" --given "<Given … when … then …>" [--given …] [--priority P0]
#                   [--platform web] [--method M] [--source <evidence>] [--spec <path> | --command "<cmd>"]
#                                   add a defect found during the run as a new I-### item (additive
#                                   amendment, applies at once), so it gets fixed and verified like any item
#   ledger.sh owner <ID> "<owner action>" "<check cmd>"   request an owner action (the verifier reviews it,
#                                   owner mode); ledger.sh owner --apply <ID> records it as needs_owner after
#                                   APPROVE. The check must fail now and exit 0 once the owner has acted.
#                                   Only for what the owner alone can provide; refuses a check that just
#                                   re-runs the item's own test ("needs an engineer" is research, not an owner action)
#   ledger.sh owner-check           re-run owner checks; reopen items whose check now passes
#   ledger.sh done-check            which terminal STATUS the ledger supports: LAUNCH_READY,
#                                   READY_FOR_OWNER, or OPEN <ids> (exit 1). An owner action without the
#                                   verifier's approval keeps its item open.
#   ledger.sh reopen <ID> "<why>"   back to failing with attempts 0
#   ledger.sh regress <ID> "<why>"  passing → failing (test broke)
#   ledger.sh hash                  criteria hash
#   ledger.sh check                 criteria hash matches .finish/LEDGER.lock (exit 1 if not)
#   ledger.sh brief                 check .finish/product.json — every claim's source exists and every
#                                   quote is really in it — and write .finish/PRODUCT.md (exit 1 on errors)
#   ledger.sh lock                  first freeze: needs a valid brief and the verifier's APPROVE (freeze
#                                   mode) for exactly this brief and ledger — writes .finish/freeze/request.md
#                                   and exits 3 until then; then writes .finish/FREEZE + .finish/LEDGER.lock
#   ledger.sh freeze-check          the first freeze was approved for the brief and ledger it froze (runner)
#   ledger.sh amend "<why>"         change the definition of done from .finish/ledger.proposed.json
#   ledger.sh amend --rebaseline "<why>"   move FREEZE to HEAD (a gate change tamper.sh flags)
#   ledger.sh amend --apply <NNN>   apply an amendment the verifier approved
#   ledger.sh amend-verify <lock> <freeze> <count> <ledger>   re-check the amendment chain (used by the runner)
#   ledger.sh migrate               reopen items left in the old blocked_human status, and old
#                                   "needs an engineer" owner hand-offs (they go back to research rounds)

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git jq

ROOT="$(fl_root)"
FD="$ROOT/.finish"
LEDGER="$FD/ledger.json"
BRIEF="$FD/product.json"
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
  local errs brief=null
  # With a brief, the ledger is built on it: same product and promise, and every item cites the
  # claims it comes from (defects found later cite their evidence instead).
  if [[ -f "$BRIEF" ]]; then brief="$(jq -c . "$BRIEF" 2>/dev/null)" || fl_die ".finish/product.json is not valid JSON"; fi
  errs="$(jq -r --arg st "$FL_STATUSES" --arg ty "$FL_TYPES" --arg me "$FL_METHODS" --argjson brief "$brief" '
    ($st | split(" ")) as $S | ($ty | split(" ")) as $T | ($me | split(" ")) as $M |
    def err(id; m): "\(id): \(m)";
    [
      (if (.product | type) != "string" or .product == "" then "ledger: product must be a non-empty string" else empty end),
      (if (.one_liner | type) != "string" or .one_liner == "" then "ledger: one_liner must be a non-empty string" else empty end),
      (if (.items | type) != "array" or (.items | length) == 0 then "ledger: items must be a non-empty array" else empty end),
      ((.items // []) | group_by(.id)[] | select(length > 1) | "\(.[0].id): duplicate id"),
      ((.items // [])[] | . as $i | ($i.id // "?") as $id |
        (if ($id | test("^[A-Z]+-[0-9]{3}$")) | not then err($id; "id must look like J-001 / F-001 / G-001 / I-001") else empty end),
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
      (if any((.items // [])[]; .priority == "P0" and .type == "journey") | not then "ledger: at least one P0 journey required" else empty end),
      (if $brief == null then empty else
        ([($brief.claims // [])[] | objects | select((.id | type) == "string") | {key: .id, value: (.basis // "")}] | from_entries) as $C |
        (if .product != $brief.product then "ledger: product must be the brief'"'"'s (.finish/product.json): \($brief.product)" else empty end),
        (if .one_liner != $brief.one_liner then "ledger: one_liner must be the brief'"'"'s: \($brief.one_liner)" else empty end),
        ((.items // [])[] | select(.type != "issue") | . as $i | (($i.source // "") | tostring | [scan("B-[0-9]{3}")]) as $cited |
          (if ($cited | length) == 0 then err($i.id; "source must cite the brief claims this item comes from, e.g. \"B-003, B-007\"") else empty end),
          ($cited[] | select($C[.] == null) | err($i.id; "cites \(.), which isn'"'"'t in the brief")),
          (if ($i.type == "journey" or $i.type == "feature") and ($cited | length) > 0 and all($cited[]; $C[.] != null)
              and ([$cited[] | $C[.] | select(. == "doc" or . == "seen")] | length) == 0
           then err($i.id; "a \($i.type) must rest on a doc or seen claim, never on code alone") else empty end))
      end)
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
# Research rounds an item has had (legacy "round 2:" notes count as one).
rounds='((.notes // "") | [scan("research round [0-9]+|round 2:")] | length)'

cmd_status() {
  local scope status
  scope="$(fl_scope_n "$FD")"
  status="$(tr -d '[:space:]' 2>/dev/null < "$FD/STATUS" || echo NEW)"
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
    (\$in | map(select(.status == \"stuck\")) | sort_by($rounds) | .[0]) as \$stuck |
    (if \$next then \"Next: \(\$next.id) — \(\$next.title) (attempts \(\$next.attempts)/3)\"
     elif \$stuck then \"Next: research round \((\$stuck | $rounds) + 1) for \(\$stuck.id) — \(\$stuck.title) (ledger.sh round \(\$stuck.id))\"
     else \"Next: none (see needs_owner)\" end)
  " "$LEDGER"
}

cmd_next() {
  need_ledger
  local scope out
  scope="$(fl_scope_n "$FD")"
  if [[ "${1:-}" == "--stuck" ]]; then
    out="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope) | select(.status == \"stuck\")] | sort_by($rounds) | .[0].id // empty" "$LEDGER")"
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"; return 0
  fi
  out="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope) | select(.status == \"failing\" and .attempts < 3)] | .[0] // empty | \"\(.id)\t\(.title)\"" "$LEDGER")"
  if [[ -z "$out" ]]; then
    echo "none"
    jq -r --argjson scope "$scope" ".items[] | select($in_scope) | select(.status == \"stuck\" or .status == \"needs_owner\") | \"  \(.status): \(.id) — \(.title)\(if .status == \"stuck\" then \" (research rounds so far: \($rounds))\" else \"\" end)\"" "$LEDGER"
    return 1
  fi
  printf '%s\n' "$out"
}

cmd_open() {
  need_ledger
  local scope
  scope="$(fl_scope_n "$FD")"
  jq -r --argjson scope "$scope" ".items[] | select($in_scope) | select(.status != \"passing\")
    | \"\(.status): \(.id) — \(.title)\(if .status == \"stuck\" or $rounds > 0 then \" (research rounds: \($rounds))\" else \"\" end)\"" "$LEDGER"
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
  [[ "$(item_field "$id" status)" == "failing" ]] || fl_die "$id is $(item_field "$id" status); only failing items can pass (stuck items: ledger.sh round $id)"
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
    echo "$id → stuck after $a attempts: paused, not abandoned. Write what you tried and ruled out in .finish/research/$id.md, then take the next item; $id comes back as a research round (protocol §5.1)."
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

# The research ladder (protocol §5.1). Round n works step min(n, 7) and keeps everything learned before.
ladder_step() {
  case "$1" in
    1) echo "reproduce it alone with full output; read the whole code path and the docs; use the debug companion" ;;
    2) echo "primary sources: docs for the installed version, type definitions, the library's own source and changelog" ;;
    3) echo "other people's reports: search the exact error; the library's GitHub issues, discussions and examples" ;;
    4) echo "isolate: a minimal reproduction outside the app; git bisect if it ever worked" ;;
    5) echo "change approach: another API or library that keeps the documented behaviour (decide per §7, log it)" ;;
    6) echo "re-scope only if the docs allow it: split the item by amendment, every criterion kept" ;;
    *) echo "fresh angle: rule out every hypothesis in .finish/research/<ID>.md with evidence, then widen the search" ;;
  esac
}

cmd_round() {
  local id="$1" n
  need_ledger; need_item "$id"
  [[ "$(item_field "$id" status)" == "stuck" ]] || fl_die "$id is $(item_field "$id" status); only stuck items get a research round"
  n="$(jq -r --arg id "$id" ".items[] | select(.id == \$id) | $rounds" "$LEDGER")"
  n=$((n + 1))
  set_status "$id" failing "research round $n: $(ladder_step "$n")" " | .attempts = 0" >/dev/null
  echo "$id → failing, research round $n: $(ladder_step "$n")"
  echo "Read .finish/research/$id.md first; log this round there (hypothesis · evidence · sources · change · result) and commit it."
}

ISSUE_ARGS='--title "<t>" --given "<Given …, when …, then …>" [--given …] [--priority P0|P1|P2] [--platform web|android|ios|api|cli] [--method e2e-web|e2e-mobile|api|command] [--source <evidence>] [--spec <path> | --command "<cmd>"]'
cmd_issue() {
  need_ledger
  [[ -f "$FD/FREEZE" ]] || fl_die "not frozen yet — add the defect to .finish/ledger.json directly before ledger.sh lock"
  local title="" priority="" platform="" source="" spec="" command="" crit='[]' id n method=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="${2:-}"; shift ;;
      --given) crit="$(jq -c --arg c "${2:-}" '. + [$c]' <<< "$crit")"; shift ;;
      --priority) priority="${2:-}"; shift ;;
      --platform) platform="${2:-}"; shift ;;
      --source) source="${2:-}"; shift ;;
      --spec) spec="${2:-}"; shift ;;
      --command) command="${2:-}"; shift ;;
      --method) method="${2:-}"; shift ;;
      *) fl_die "unknown argument: $1 — usage: ledger.sh issue $ISSUE_ARGS" ;;
    esac
    shift
  done
  [[ -n "$title" && "$crit" != '[]' ]] || fl_die "usage: ledger.sh issue $ISSUE_ARGS"
  [[ -n "$priority" ]] || priority="P$(fl_scope_n "$FD")"
  local dup
  dup="$(jq -r --arg t "$title" '[.items[] | select(.type == "issue" and (.title | ascii_downcase) == ($t | ascii_downcase)) | .id][0] // empty' "$LEDGER")"
  [[ -z "$dup" ]] || fl_die "already filed as $dup — work that item (ledger.sh show $dup)"
  n="$(jq -r '[.items[].id | select(test("^I-[0-9]{3}$")) | ltrimstr("I-") | tonumber] | max // 0' "$LEDGER")"
  id="$(printf 'I-%03d' $((n + 1)))"
  # The platform decides how it is verified (an API test may well be named *.spec.ts); --method overrides.
  # With neither, the spec path must say it unambiguously, or the call is refused.
  if [[ -z "$platform" && -z "$method" && -z "$command" && -n "$spec" ]]; then
    case "$spec" in
      e2e/*.spec.ts|e2e/*.spec.js|*/e2e/*.spec.ts|*/e2e/*.spec.js) platform=web ;;
      .maestro/*|*/.maestro/*|*.yaml|*.yml) fl_die "a Maestro flow: say which platform — --platform android or --platform ios" ;;
      *) fl_die "can't tell how $spec runs: give --platform (web, android, ios, api, cli) or --method" ;;
    esac
  fi
  [[ -n "$platform" ]] || platform=web
  if [[ -n "$command" ]]; then method="command"
  elif [[ -z "$method" ]]; then
    case "$platform" in web) method=e2e-web ;; android|ios) method=e2e-mobile ;; *) method=api ;; esac
  fi
  case " $FL_METHODS " in *" $method "*) ;; *) fl_die "--method must be one of: $FL_METHODS" ;; esac
  [[ "$method" != command || -n "$command" ]] || fl_die "--method command needs --command \"<cmd>\""
  if [[ -z "$spec" && "$method" != command ]]; then
    case "$method" in
      e2e-web) spec="e2e/finish/$id.spec.ts" ;;
      e2e-mobile) spec=".maestro/finish/$id.yaml" ;;
      *) fl_die "$method has no default spec path: give --spec <tests/finish/…>" ;;
    esac
  fi
  jq --arg id "$id" --arg t "$title" --arg p "$priority" --arg pl "$platform" --arg src "${source:-found during the run}" \
     --arg m "$method" --arg sp "$spec" --arg cmd "$command" --argjson crit "$crit" '
    .items += [{id: $id, type: "issue", priority: $p, platforms: [$pl], title: $t, source: $src, acceptance: $crit,
                verify: (if $m == "command" then {method: $m, command: $cmd} else {method: $m, spec: $sp} end),
                status: "failing", attempts: 0, evidence: [], notes: ""}]' "$LEDGER" > "$PROPOSED" \
    || fl_die "could not build the proposed ledger"
  cmd_amend "defect $id: $title" || return $?
  echo "$id added ($priority, $method${spec:+ $spec}). Work it like any item: test first (protocol §5a)."
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

committed() { # <path>: tracked and unchanged since HEAD
  git ls-files --error-unmatch "$1" >/dev/null 2>&1 && git diff --quiet HEAD -- "$1" 2>/dev/null
}

cmd_lock() {
  need_ledger
  [[ "${1:-}" == "--apply" ]] && shift   # same as lock: it freezes once the review approves
  local refreeze=0 rc
  [[ "${1:-}" == "--refreeze" ]] && refreeze=1
  if [[ -f "$FD/FREEZE" && $refreeze -eq 0 ]]; then
    fl_die "ledger already frozen at $(cat "$FD/FREEZE"). Change the definition of done with: ledger.sh amend \"<why>\""
  fi
  if [[ ! -f "$FD/FREEZE" ]]; then   # the first freeze: the brief comes first, and the verifier approves both
    [[ -f "$BRIEF" ]] || fl_die "no product brief — write .finish/product.json from the docs (protocol §3.2) before the ledger can freeze"
    cmd_brief >/dev/null || { cmd_brief; fl_die "the brief doesn't check out — fix .finish/product.json"; }
  fi
  cmd_validate >/dev/null || { cmd_validate; fl_die "ledger invalid"; }
  committed .finish/ledger.json || fl_die "commit .finish/ledger.json first; FREEZE must point at the commit that contains it"
  if [[ ! -f "$FD/FREEZE" ]]; then
    committed .finish/product.json || fl_die "commit .finish/product.json (and .finish/PRODUCT.md) first; FREEZE must point at the commit that contains the brief"
    freeze_request; rc=$?
    [[ $rc -eq 0 ]] || return "$rc"
  fi
  git rev-parse HEAD > "$FD/FREEZE"
  fl_criteria_hash "$LEDGER" > "$FD/LEDGER.lock"
  echo "frozen at $(cat "$FD/FREEZE") · criteria $(cat "$FD/LEDGER.lock")"
  echo "now: git add .finish/FREEZE .finish/LEDGER.lock .finish/freeze && git commit -m \"chore(finish): freeze ledger\""
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

# ── The product brief ─────────────────────────────────────────────────────────
# .finish/product.json is what the run understands the product to be, one claim per fact, each
# resting on a source: a doc (with a verbatim quote), something watched in the running app (a
# screenshot or log), or code (what exists, never what it's for). `brief` checks that every
# quote really is in its source, so the understanding can't drift from what the docs say.

# Text as compared for quotes: one line, collapsed spaces, lower case, typographic quotes and
# dashes made plain, markdown emphasis and code marks dropped.
FLAT_SED="$(printf "s/\xe2\x80\x99/'/g; s/\xe2\x80\x98/'/g; s/\xe2\x80\x9c/\"/g; s/\xe2\x80\x9d/\"/g; s/\xe2\x80\x94/-/g; s/\xe2\x80\x93/-/g; s/\xc2\xa0/ /g")"
flat() { LC_ALL=C sed -e "$FLAT_SED" | LC_ALL=C tr '\r\n\t' '   ' | LC_ALL=C tr -d '*`' | LC_ALL=C tr -s ' ' | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

brief_kind() { # <file> → image | pdf | text | binary
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.svg|*.avif|*.heic|*.fig|*.sketch) echo image; return ;;
    *.pdf) echo pdf; return ;;
  esac
  if [[ ! -s "$1" ]] || grep -Iq . "$1" 2>/dev/null; then echo text; else echo binary; fi
}

brief_quote_found() { # <file> <kind> <quote>
  local q
  q="$(printf '%s' "$3" | flat)"; q="${q# }"; q="${q% }"
  if [[ "$2" == pdf ]]; then pdftotext -q "$1" - 2>/dev/null | flat | grep -qF -e "$q"
  else flat < "$1" | grep -qF -e "$q"; fi
}

cmd_brief() {
  [[ -f "$BRIEF" ]] || fl_die "no brief at .finish/product.json — write it from the docs first (protocol §3.2; template: \$FINISH_SKILL_DIR/templates/product.example.json)"
  jq -e 'type == "object"' "$BRIEF" >/dev/null 2>&1 || fl_die ".finish/product.json is not a JSON object"
  local errs rec id basis src quote file kind unchecked="" words
  errs="$(jq -r '
    [
      (if (.product | type) != "string" or .product == "" then "brief: product must be a non-empty string" else empty end),
      (if (.one_liner | type) != "string" or .one_liner == "" then "brief: one_liner must be a non-empty string" else empty end),
      (if (.claims | type) != "array" or (.claims | length) == 0 then "brief: claims must be a non-empty array" else empty end),
      (if (.docs | type) != "array" then "brief: docs must list every doc you read in full (an array of paths)" else empty end),
      (if (.unknowns | type) != "array" then "brief: unknowns must be an array (empty only when the docs answer everything)" else empty end),
      ((.claims // []) | map(select(type == "object")) | group_by(.id)[] | select(length > 1) | "\(.[0].id): duplicate claim id"),
      ((.claims // [])[] | . as $c | (if type == "object" then (.id // "?") else "?" end) as $id |
        if type != "object" then "brief: every claim is an object" else
        (if ($id | tostring | test("^B-[0-9]{3}$")) | not then "\($id): claim id must look like B-001" else empty end),
        (if (["doc","seen","code"] | index($c.basis)) == null then "\($id): basis must be doc, seen or code" else empty end),
        (if ($c.claim | type) != "string" or $c.claim == "" then "\($id): claim text required" else empty end),
        (if ($c.source | type) != "string" or $c.source == "" then "\($id): source required (a file path)" else empty end),
        (if has("quote") and (.quote | type) != "string" then "\($id): quote must be a string" else empty end)
        end),
      ([(.claims // [])[] | objects | select((.id | type) == "string") | {key: .id, value: (.basis // "")}] | from_entries) as $B |
      (if (.one_liner_claims | type) != "array" or (.one_liner_claims | length) == 0
       then "brief: one_liner_claims must name the doc or seen claims the one_liner rests on"
       else (.one_liner_claims[] | select((type != "string") or (($B[.] // "") | IN("doc", "seen") | not))
             | "brief: one_liner_claims: \(.) is not a doc or seen claim in this brief") end),
      ((.unknowns // []) | if type == "array" then .[] | select(type != "string" or . == "") | "brief: every unknown is a non-empty string" else empty end),
      ((.docs // []) | if type == "array" then .[] | select(type != "string" or . == "") | "brief: every docs entry is a path" else empty end)
    ] | .[]' "$BRIEF" 2>&1)"

  # Every source is a file in the repo; every quote is really in its source.
  local docs
  docs="$(jq -r '.docs // [] | if type == "array" then .[] | strings else empty end' "$BRIEF")"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ -e "$file" ]] || errs="$errs${errs:+$'\n'}brief: docs lists $file, which doesn't exist"
  done <<< "$docs"
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    id="$(jq -r '.id' <<< "$rec")"; basis="$(jq -r '.basis' <<< "$rec")"
    src="$(jq -r '.source' <<< "$rec")"; quote="$(jq -r '.quote' <<< "$rec")"
    file="${src%%#*}"; file="$(printf '%s' "$file" | sed -E 's/:[0-9]+(-[0-9]+)?$//')"
    local e=""
    case "$file" in /*|../*|*/../*|..) e="source must be a path inside the repo" ;; esac
    if [[ -z "$e" && ! -f "$file" ]]; then e="source $file doesn't exist"; fi
    if [[ -z "$e" ]]; then
      case "$basis:$file" in
        doc:.finish/sources/*) ;;
        seen:.finish/evidence/*) ;;
        seen:*) e="a seen claim cites what you captured in .finish/evidence/ (a screenshot, a log)" ;;
        *:.finish/*) e="$file is the run's own notes, not a source about the product" ;;
      esac
    fi
    if [[ -z "$e" ]] && fl_is_protected_path "$file"; then e="$file is one of Finish Line's own tests, not a source about the product"; fi
    if [[ -z "$e" && "$basis" == doc ]] && ! printf '%s\n' "$docs" | grep -qxF -- "$file"; then
      e="$file isn't in docs (list every doc you read)"
    fi
    if [[ -z "$e" ]]; then
      kind="$(brief_kind "$file")"
      if [[ "$kind" == pdf ]] && ! command -v pdftotext >/dev/null 2>&1; then kind=image; fi
      if [[ -n "$quote" && "$kind" != image && "$kind" != binary ]]; then
        words="$(printf '%s' "$quote" | wc -w | tr -d ' ')"
        if [[ "$words" -lt 3 ]]; then e="quote is too short to locate (3 words or more, copied verbatim)"
        elif ! brief_quote_found "$file" "$kind" "$quote"; then e="quote not found in $file — copy it verbatim from the file, or drop the claim"; fi
      elif [[ "$basis" != seen && "$kind" == text ]]; then
        e="a $basis claim needs the verbatim quote from $file that it rests on"
      elif [[ "$kind" == image || "$kind" == binary ]]; then
        unchecked="$unchecked $id"
      fi
    fi
    [[ -z "$e" ]] || errs="$errs${errs:+$'\n'}$id: $e"
  done < <(jq -c '(.claims // [])[]? | objects | select((.source | type) == "string") | {id: (.id // "?"), basis: (.basis // ""), source, quote: ((.quote // "") | tostring)}' "$BRIEF" 2>/dev/null)

  if [[ -n "$errs" ]]; then
    printf '%s\n' "$errs"
    echo "BRIEF: INVALID ($(printf '%s\n' "$errs" | wc -l | tr -d ' ') errors)"
    return 1
  fi
  jq -r '"BRIEF: VALID (\(.claims | length) claims: \([.claims[] | select(.basis == "doc")] | length) doc, \([.claims[] | select(.basis == "seen")] | length) seen, \([.claims[] | select(.basis == "code")] | length) code · \(.unknowns | length) unknowns)"' "$BRIEF"
  [[ -z "$unchecked" ]] || echo "not machine-checked (images, PDFs): ${unchecked# } — the verifier opens these itself"
  brief_md
}

brief_md() { # .finish/PRODUCT.md: the brief, readable — what the run thinks the product is
  jq -r '
    def cites: "(\(. | join(", ")))";
    def line: "- **\(.id)** \(.claim) — `\(.source)`" + (if (.quote // "") != "" then ": “\(.quote)”" else "" end);
    "# \(.product) — the product as this run understands it",
    "",
    "> \(.one_liner) \(.one_liner_claims | cites)",
    "",
    "Built only from the docs and the running app. Every line cites its source, and `ledger.sh brief` checks each quote against it. If something here is wrong, the docs are unclear: fix them and start fresh (`finish.sh --fresh`).",
    "",
    "## What the docs say",
    ([.claims[] | select(.basis == "doc") | line] | if length > 0 then .[] else "None." end),
    "",
    "## Seen in the running app",
    ([.claims[] | select(.basis == "seen") | line] | if length > 0 then .[] else "None." end),
    "",
    "## What exists in the code",
    ([.claims[] | select(.basis == "code") | line] | if length > 0 then .[] else "None." end),
    "",
    "## Unknown — the docs don'"'"'t say",
    (.unknowns | if length > 0 then .[] | "- \(.)" else "None." end),
    "",
    "## Docs read",
    (.docs | if length > 0 then .[] | "- `\(.)`" else "None." end)' "$BRIEF" > "$FD/PRODUCT.md"
}

# ── Freeze review ─────────────────────────────────────────────────────────────
# Everything after the freeze is built on the brief and the ledger, so the first freeze needs
# the verifier's APPROVE (freeze mode) for exactly this brief and this ledger.

FREEZE_DIR="$FD/freeze"

freeze_request() { # write .finish/freeze/request.md; 0 when the verifier approved exactly it, 3 when it waits
  local req="$FREEZE_DIR/request.md" rev="$FREEZE_DIR/review.md" tmp
  mkdir -p "$FREEZE_DIR"
  tmp="$(mktemp)"
  {
    echo "# Freeze request — $(jq -r .product "$LEDGER")"
    echo
    echo "BRIEF: $(fl_sha < "$BRIEF")"
    echo "LEDGER: $(fl_criteria_hash "$LEDGER")"
    echo
    echo "Everything the run builds rests on .finish/product.json and .finish/ledger.json. Check both against the docs."
    echo
    echo "## Brief check"; echo '```'; cmd_brief 2>&1; echo '```'
    echo
    echo "## Items"
    jq -r '.items[] | "- \(.id) (\(.priority) \(.type)) — \(.title) — source: \(.source // "")"' "$LEDGER"
  } > "$tmp"
  if cmp -s "$tmp" "$req"; then rm -f "$tmp"; else mv "$tmp" "$req"; rm -f "$rev"; fi
  if [[ -f "$rev" ]] && grep -Eq "^REQUEST: *$(fl_sha < "$req")" "$rev"; then
    grep -Eq '^VERDICT: *APPROVE' "$rev" && return 0
    fl_die "the verifier rejected the brief or the ledger: fix what .finish/freeze/review.md lists (re-read the sources it names), commit, then ledger.sh lock again"
  fi
  echo "freezing needs the verifier's approval of the brief and the ledger. Spawn finish-verifier in freeze mode with: .finish/freeze/request.md"
  echo "then: ledger.sh lock   (REJECT → fix what its review lists, commit, lock again)"
  return 3
}

cmd_freeze_check() { # the first freeze carries an APPROVE for the brief and ledger it froze
  [[ -f "$FD/FREEZE" ]] || { echo "not frozen yet"; return 0; }
  local req="$FREEZE_DIR/request.md" rev="$FREEZE_DIR/review.md" f0 tmp l
  [[ -f "$req" && -f "$rev" ]] || { echo "no freeze request and review in .finish/freeze/"; return 1; }
  if ! grep -Eq "^REQUEST: *$(fl_sha < "$req")" "$rev" || ! grep -Eq '^VERDICT: *APPROVE' "$rev"; then
    echo "the freeze review doesn't approve this request"; return 1
  fi
  f0="$(jq -rs '.[0].freeze_before // empty' "$FD/amendments.jsonl" 2>/dev/null)"
  [[ -n "$f0" ]] || f0="$(tr -d '[:space:]' < "$FD/FREEZE")"
  git cat-file -e "$f0:.finish/product.json" 2>/dev/null || { echo "the freeze commit has no .finish/product.json"; return 1; }
  grep -qxF "BRIEF: $(git show "$f0:.finish/product.json" | fl_sha)" "$req" || { echo "the brief at the freeze isn't the one reviewed"; return 1; }
  tmp="$(mktemp)"; git show "$f0:.finish/ledger.json" > "$tmp" 2>/dev/null; l="$(fl_criteria_hash "$tmp" 2>/dev/null)"; rm -f "$tmp"
  grep -qxF "LEDGER: $l" "$req" || { echo "the ledger at the freeze isn't the one reviewed"; return 1; }
  echo "FREEZE REVIEW: OK"
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

# Owner actions are what only the owner can provide. Unsolved engineering work never is:
#   - hand-off wording is refused outright;
#   - an action that starts with an engineering verb is refused unless it names an owner boundary
#     ("Fix the DNS records for the production domain" is the owner's; "Fix the login bug" isn't);
#   - a check that runs a test suite, or the item's own spec, would detect the fix rather than
#     anything the owner did. A plain credential/account check (test -n "$KEY", <cli> whoami) is fine,
#     even when it is the item's own frozen verify.command;
#   - the check must fail now (cmd_owner runs it): one that already passes waits on nobody;
#   - then the independent verifier decides (owner mode), and only --apply after its APPROVE records it.
HANDOFF_RE='needs? (an? )?(engineer|developer|human|person|someone)|someone (to|must|should|who)|manual(ly)? (fix|debug)|could ?n.?t (fix|figure)|unable to (fix|figure|get it)|don.?t know how'
ENG_VERB_RE='^[[:space:]]*(fix|debug|investigate|implement|refactor|rewrite|diagnose)([^A-Za-z]|$)|(fix|debug)(es|ing)? (it|this|that|the (bug|issue|code|test|error))'
OWNER_TOPIC_RE='dns|domain|registrar|production|credentials?|api key|secret key|billing|subscription|paid plan|app store|play console|testflight|store listing|legal|certificate|signing identity'
TEST_RUNNER_RE='playwright|vitest|jest|pytest|mocha|cypress|maestro|go test|cargo test|(npm|pnpm|yarn|bun)( run)? test|gradlew|xcodebuild|flutter test|verify\.sh|ledger\.sh'
# A check that runs the product's own code or local app tests behaviour, not the owner's step.
# Commands count only in command position (start, or after ; & | ( ` $( ), so a path argument
# such as `test -s ./certs/dist.p12` or `grep -q node package.json` is fine.
# shellcheck disable=SC2016  # a literal backtick in a regex
REPO_CODE_RE='(^|[;&|(`]|\$\()[[:space:]]*((node|python3?|ruby|php|perl|deno|tsx|ts-node|bash|sh|zsh)[[:space:]]+[^-[:space:]]|(npm|pnpm|yarn|bun)[[:space:]]+(run|exec|start)|\.{1,2}/|make([[:space:]]|$)|(go|cargo)[[:space:]]+run)|(localhost|127\.0\.0\.1|0\.0\.0\.0)'

not_owner() { # <ID> <action> <check> [--legacy] → exit 0 (with the reason) when this isn't a real owner action
  # --legacy (migrate): only the high-precision signals, since a false positive there deletes a task
  # the owner still has to do; new requests also get the broader rules, then the verifier's review.
  local id="$1" action="$2" check="$3" legacy="${4:-}" spec
  spec="$(item_verify "$id" spec)"
  if printf '%s\n' "$action" | grep -qiE "$HANDOFF_RE"; then echo "the action hands over engineering work"; return 0; fi
  if [[ -n "$spec" && "$check" == *"$spec"* ]] || printf '%s\n' "$check" | grep -qiE "$TEST_RUNNER_RE"; then
    echo "the check runs a test, so it detects the fix, not anything the owner did"; return 0
  fi
  [[ "$legacy" == --legacy ]] && return 1
  if printf '%s\n' "$action" | grep -qiE "$ENG_VERB_RE" && ! printf '%s\n' "$action" | grep -qiE "$OWNER_TOPIC_RE"; then
    echo "the action is engineering work, not something only the owner can provide"; return 0
  fi
  if printf '%s\n' "$check" | grep -qE "$REPO_CODE_RE"; then
    echo "the check runs the product's own code or local app, so it detects the fix, not anything the owner did"; return 0
  fi
  return 1
}

OWNER_DIR="$FD/owner"

cmd_owner() {
  [[ "${1:-}" == "--apply" ]] && { owner_apply "${2:-}"; return $?; }
  local id="$1" action="${2:-}" check="${3:-}" req rc
  need_ledger; need_item "$id"
  [[ -n "$action" ]] || fl_die "owner needs the exact action, e.g. \"Add STRIPE_SECRET_KEY (test mode) to .env.local\""
  [[ -n "$check" ]] || fl_die "owner needs a check command that exits 0 once the action is done, e.g. 'grep -q ^STRIPE_SECRET_KEY= .env.local'"
  local why
  if ! why="$(not_owner "$id" "$action" "$check")" && run_limited "${FINISH_OWNER_CHECK_TIMEOUT:-60}" "$check"; then
    why="the check already passes, so nothing is waiting on the owner (it must fail until the owner acts)"
  fi
  if [[ -n "$why" ]]; then
    fl_die "refusing: not an owner action — $why. If only the code is missing, the work is yours: ledger.sh fail $id, then research rounds (ledger.sh round $id, protocol §5.1). Owner actions are for credentials, accounts, paid plans, production, real emails/payments, DNS, store listings, legal review and merging, with a check that detects the owner's step (test -n \"\$KEY\", vercel whoami, dig +short …)."
  fi
  # Judgment the text rules can't make (is "billing" a bug or the owner's Stripe account?) belongs to
  # the independent verifier, as for weakening amendments: nothing leaves the run without its APPROVE.
  run_limited "${FINISH_OWNER_CHECK_TIMEOUT:-60}" "$check"; rc=$?
  mkdir -p "$OWNER_DIR"
  req="$OWNER_DIR/$id.request.md"
  {
    echo "# Owner action request — $id"
    echo; echo "ITEM: $id"; echo "ACTION: $action"; echo "CHECK: $check"; echo "CHECK NOW: exit $rc"
    echo; echo "## The item"; echo '```json'; jq --arg id "$id" '.items[] | select(.id == $id) | del(.evidence)' "$LEDGER"; echo '```'
    if [[ -f "$FD/research/$id.md" ]]; then echo; echo "## Research so far"; head -80 "$FD/research/$id.md"; fi
  } > "$req"
  rm -f "$OWNER_DIR/$id.review.md"
  echo "owner action for $id needs review. Spawn finish-verifier in owner mode with: ${req#"$ROOT"/}"
  echo "then: ledger.sh owner --apply $id   (REJECT → it's yours: keep working it, protocol §5.1)"
  return 3
}

owner_approved() { # <ID>: its owner action carries the verifier's APPROVE for the exact request
  local id="$1" req="$OWNER_DIR/$1.request.md" rev="$OWNER_DIR/$1.review.md" h
  [[ -f "$req" && -f "$rev" && -f "$OWNER" ]] || return 1
  h="$(fl_sha < "$req")"
  grep -Eq "^REQUEST: *$h" "$rev" && grep -Eq '^VERDICT: *APPROVE' "$rev" \
    && jq -e --arg id "$id" --arg h "$h" '.[$id].request == $h' "$OWNER" >/dev/null 2>&1
}

owner_request_legacy() { # <ID> <action> <check>: write a review request for an owner action recorded before reviews existed (1 = already there)
  local id="$1" req="$OWNER_DIR/$1.request.md"
  mkdir -p "$OWNER_DIR"
  [[ -f "$req" ]] && return 1   # already requested (owner-check keeps listing it until reviewed)
  {
    echo "# Owner action request — $id (recorded before owner reviews existed)"
    echo; echo "ITEM: $id"; echo "ACTION: $2"; echo "CHECK: $3"; echo "CHECK NOW: exit $(run_limited "${FINISH_OWNER_CHECK_TIMEOUT:-60}" "$3"; echo $?)"
    echo; echo "## The item"; echo '```json'; jq --arg id "$id" '.items[] | select(.id == $id) | del(.evidence)' "$LEDGER"; echo '```'
  } > "$req"
}

owner_apply() { # <ID>: record an owner action the verifier approved
  local id="$1" req review tmp action check
  need_ledger; need_item "$id"
  req="$OWNER_DIR/$id.request.md"; review="$OWNER_DIR/$id.review.md"
  [[ -f "$req" ]] || fl_die "no request at ${req#"$ROOT"/} — run ledger.sh owner $id \"<action>\" \"<check>\" first"
  [[ -f "$review" ]] || fl_die "no review at ${review#"$ROOT"/} — spawn finish-verifier in owner mode with: ${req#"$ROOT"/}"
  grep -Eq "^REQUEST: *$(fl_sha < "$req")" "$review" || fl_die "review is for a different request (REQUEST hash mismatch)"
  grep -Eq '^VERDICT: *APPROVE' "$review" || fl_die "the verifier rejected this owner action: the work is yours — ledger.sh fail $id / ledger.sh round $id (protocol §5.1)"
  action="$(sed -n 's/^ACTION: //p' "$req" | head -1)"; check="$(sed -n 's/^CHECK: //p' "$req" | head -1)"
  run_limited "${FINISH_OWNER_CHECK_TIMEOUT:-60}" "$check" && fl_die "the check passes now, so nothing is waiting on the owner; keep working $id"
  set_status "$id" needs_owner "owner action (verifier-approved): $action"
  [[ -f "$OWNER" ]] || echo '{}' > "$OWNER"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg a "$action" --arg c "$check" --arg t "$(fl_now)" --arg r "$(fl_sha < "$req")" \
    '.[$id] = {action: $a, check: $c, since: $t, request: $r}' "$OWNER" > "$tmp" && mv "$tmp" "$OWNER"
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
  local unreviewed="" k
  for k in $(jq -r 'keys[]' "$OWNER"); do
    [[ "$(item_field "$k" status)" == "needs_owner" ]] && ! owner_approved "$k" && unreviewed="$unreviewed $k"
  done
  if [[ -n "$reopened" ]]; then echo "owner-check: reopened$reopened"; else echo "owner-check: still waiting on $(jq 'length' "$OWNER")"; fi
  [[ -z "$unreviewed" ]] || echo "owner-check: awaiting the verifier's review (owner mode, .finish/owner/<ID>.request.md):$unreviewed"
}

# Products started before needs_owner existed: reopen their blocked_human items so the
# agent re-evaluates them and, if still needed, records a proper owner action with a check.
cmd_migrate() {
  need_ledger
  local ids tmp id
  ids="$(jq -r '.items[] | select(.status == "blocked_human") | .id' "$LEDGER")"
  for id in $ids; do
    set_status "$id" failing "migrated from blocked_human: re-evaluate; if it still needs the owner, record ledger.sh owner with a check" " | .attempts = 0" >/dev/null
  done
  # Older runs could hand an unsolved item to the owner as "Needs an engineer": that work is the run's.
  local done_eng="" review_eng=""
  if [[ -f "$OWNER" ]]; then
    local rec action check
    while IFS= read -r rec; do
      [[ -n "$rec" ]] || continue
      id="$(jq -r '.[0]' <<< "$rec")"; action="$(jq -r '.[1]' <<< "$rec")"; check="$(jq -r '.[2]' <<< "$rec")"
      [[ "$(item_field "$id" status)" == "needs_owner" ]] || continue
      owner_approved "$id" && continue
      if ! not_owner "$id" "$action" "$check" --legacy >/dev/null; then
        # Not clearly a hand-off, but never reviewed: the verifier decides before it can count as the owner's.
        owner_request_legacy "$id" "$action" "$check" && review_eng="$review_eng $id"
        continue
      fi
      set_status "$id" stuck "an engineering hand-off isn't an owner action: back to research rounds" >/dev/null
      tmp="$(mktemp)"; jq --arg id "$id" 'del(.[$id])' "$OWNER" > "$tmp" && mv "$tmp" "$OWNER"
      done_eng="$done_eng $id"
    done < <(jq -c 'to_entries[] | [.key, .value.action, .value.check]' "$OWNER" 2>/dev/null)
    owner_md
  fi
  ids="$(printf '%s %s' "$ids" "$done_eng" | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
  review_eng="${review_eng# }"
  [[ -n "$ids" || -n "$review_eng" ]] || { echo "migrate: nothing to do"; return 0; }
  [[ -z "$ids" ]] || echo "migrate: reopened $ids"
  [[ -z "$review_eng" ]] || echo "migrate: owner actions awaiting the verifier's review: $review_eng"
}

cmd_done_check() {
  need_ledger
  local scope out
  scope="$(fl_scope_n "$FD")"
  local open owners id unreviewed=""
  open="$(jq -r --argjson scope "$scope" "[.items[] | select($in_scope) | select(.status != \"passing\" and .status != \"needs_owner\") | .id] | join(\" \")" "$LEDGER")"
  owners="$(jq -r --argjson scope "$scope" ".items[] | select($in_scope) | select(.status == \"needs_owner\") | .id" "$LEDGER")"
  for id in $owners; do owner_approved "$id" || unreviewed="$unreviewed $id"; done
  open="$(printf '%s%s' "$open" "$unreviewed" | sed 's/^ *//')"
  if [[ -n "$open" ]]; then out="OPEN $open"
  elif [[ -n "$owners" ]]; then out="READY_FOR_OWNER"
  else out="LAUNCH_READY"; fi
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
    grep -Eq '^VERDICT: *APPROVE' "$review" || fl_die "the verifier did not approve amendment $applyn — keep working the item (research rounds, protocol §5.1)"
    grep -Eq "^REQUEST: *$reqhash" "$review" || fl_die "review $applyn is for a different request (REQUEST hash mismatch)"
    [[ "$(amd_weakening_count)" -lt "${FINISH_MAX_AMENDMENTS:-5}" ]] || fl_die "amendment cap reached (${FINISH_MAX_AMENDMENTS:-5}); the criteria stand — keep working the item (research rounds, protocol §5.1)"
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
    if ! git diff --quiet "$freeze_before" HEAD -- .finish/product.json 2>/dev/null && ! cmd_brief >/dev/null; then
      cmd_brief; fl_die "the changed brief doesn't check out — fix .finish/product.json, commit, then propose the rebaseline"
    fi
    {
      echo "# Amendment $n — rebaseline"
      echo; echo "KIND: rebaseline"; echo "REASON: $reason"; echo "HEAD: $(git rev-parse HEAD)"; echo "FREEZE: $freeze_before"
      echo; echo "## What tamper.sh flags now"; echo '```'; "$HERE/tamper.sh" 2>&1 | head -40; echo '```'
      echo; echo "## Changes since the freeze in flagged areas"; echo '```'
      git diff --stat "$freeze_before" HEAD 2>/dev/null | tail -40; echo '```'
      if ! git diff --quiet "$freeze_before" HEAD -- .finish/product.json 2>/dev/null; then
        echo; echo "## Brief changes (.finish/product.json) — check each against its source"; echo '```diff'
        git diff "$freeze_before" HEAD -- .finish/product.json 2>/dev/null | head -200; echo '```'
        echo; echo '```'; cmd_brief 2>&1; echo '```'
      fi
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
  lock="$(tr -d '[:space:]' 2>/dev/null < "$FD/LEDGER.lock")"; freeze="$(tr -d '[:space:]' 2>/dev/null < "$FD/FREEZE")"
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
  next) cmd_next "${1:-}" ;;
  open) cmd_open ;;
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
  round|round2) cmd_round "${1:-}" ;;
  issue) cmd_issue "$@" ;;
  hash) need_ledger; fl_criteria_hash "$LEDGER" ;;
  state) fl_code_state ;;
  run-commands) cmd_run_commands "${1:-}" ;;
  check) cmd_check ;;
  brief) cmd_brief ;;
  freeze-check) cmd_freeze_check ;;
  lock) cmd_lock "$@" ;;
  ""|-h|--help|help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}" ;;
  *) fl_die "unknown subcommand: $sub (try --help)" ;;
esac
