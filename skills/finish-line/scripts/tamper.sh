#!/usr/bin/env bash
# tamper.sh — fails when the Finish Line gate has been gamed.
#
#   tamper.sh [--base <sha>]     default base: .finish/FREEZE
#
# Always checked:
#   - protected tests (any path with a finish/ segment) contain no skip/only/
#     fixme/xfail/ignore/optional markers and no assertions that can't fail
#   - every spec recorded in .finish/ratchet.json still exists with at least
#     as many assertions as when its item passed; every passing item's spec exists
# Checked against the freeze commit (once the ledger is frozen):
#   - frozen criteria hash matches .finish/LEDGER.lock
#   - no test files deleted; no skip markers or tautologies added to any test
#   - test-runner configs: no changes to include/exclude/ignore/retries/only rules
#   - .finish/verify.sh: no stage removed or turned into "n/a", tamper stage intact
#   - .finish/bin/ unchanged
#
# Exit 0 = clean, 1 = tampering found, 2 = usage/environment error.
# A false positive is cleared by the human re-freezing (ledger.sh lock --refreeze).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git jq grep

ROOT="$(fl_root)"
FD="$ROOT/.finish"
cd "$ROOT" || exit 2

base=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) shift; base="${1:-}" ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fl_die "unknown argument: $1" ;;
  esac
  shift
done
[[ -z "$base" && -f "$FD/FREEZE" ]] && base="$(tr -d '[:space:]' < "$FD/FREEZE")"

CONFIG_PATH_RE='(^|/)(playwright|jest|vitest|cypress|karma|vite)\.config\.[cm]?[jt]s$|(^|/)(jest\.config\.json|pytest\.ini|tox\.ini|setup\.cfg|pyproject\.toml|package\.json|build\.gradle|build\.gradle\.kts|\.mocharc|\.mocharc\.[a-z]+)$'
CONFIG_KEY_RE='testIgnore|testPathIgnorePatterns|testMatch|testRegex|testDir|grepInvert|(^|[^A-Za-z])grep *:|exclude|norecursedirs|addopts|--ignore|--deselect|testpaths|"test(:[^"]*)?" *:|excludeTestsMatching|forbidOnly|retries|passWithNoTests|bail'
MARKER_RE="$FL_SKIP_RE|$FL_TAUTOLOGY_RE"

findings=0
report() { findings=$((findings + 1)); printf 'TAMPER: %s\n' "$*"; }
TMP="$(mktemp)"
trap 'rm -f "$TMP" "$TMP.max" "$TMP.cur"' EXIT
# Report every line a producer wrote to $TMP (producers run in subshells, so they can't count).
flush() { if [[ -s "$TMP" ]]; then while IFS= read -r l; do report "$l"; done < "$TMP"; fi; : > "$TMP"; }

all_files() { { git ls-files; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u; }

# 1. Protected tests: no markers, ever.
all_files | grep -E "$FL_PROTECTED_RE" | while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  grep -InE "$MARKER_RE" "$f" 2>/dev/null | while IFS= read -r hit; do
    printf 'protected test %s:%s\n' "$f" "$hit"
  done
done > "$TMP"
flush

# 2. Ratchet + passing specs exist. The ratchet is the max over every committed
#    version of ratchet.json, so lowering the file itself doesn't help.
if [[ -f "$FD/ratchet.json" || -n "$(git log -1 --format=%H -- .finish/ratchet.json 2>/dev/null)" ]]; then
  {
    for c in $(git log --format=%H -- .finish/ratchet.json 2>/dev/null); do git show "$c:.finish/ratchet.json" 2>/dev/null; done
    cat "$FD/ratchet.json" 2>/dev/null || true   # pipefail: a missing file must not void the history
  } | jq -s '[.[] | objects | to_entries[]] | group_by(.key)
             | map({key: .[0].key, value: {spec: .[-1].value.spec, assertions: (map(.value.assertions) | max)}}) | from_entries' \
    > "$TMP.max" 2>/dev/null || echo '{}' > "$TMP.max"
  curf="$FD/ratchet.json"
  if [[ ! -f "$curf" ]]; then echo '{}' > "$TMP.cur"; curf="$TMP.cur"; fi
  while IFS=$'\t' read -r id spec n cur; do
    [[ -n "$id" ]] || continue
    [[ "$cur" == "null" || "$cur" -lt "$n" ]] && report "ratchet: .finish/ratchet.json lowered for $id (now $cur, was $n)"
    if [[ ! -f "$spec" ]]; then
      report "ratchet: $id spec $spec was deleted after passing"
    else
      now="$(fl_assert_count "$spec")"
      [[ "${now:-0}" -ge "$n" ]] || report "ratchet: $id spec $spec has $now assertions, had $n when it passed"
    fi
  done < <(jq -r --slurpfile cur "$curf" 'to_entries[] | "\(.key)\t\(.value.spec)\t\(.value.assertions)\t\($cur[0][.key].assertions // "null")"' "$TMP.max" 2>/dev/null)
  rm -f "$TMP.max" "$TMP.cur"
fi
if [[ -f "$FD/ledger.json" ]]; then
  while IFS=$'\t' read -r id spec; do
    [[ -n "$spec" && ! -f "$spec" ]] && report "passing item $id has no spec at $spec"
  done < <(jq -r '.items[] | select(.status == "passing") | select((.verify.spec // "") != "") | "\(.id)\t\(.verify.spec)"' "$FD/ledger.json" 2>/dev/null)
fi

# 3. Everything else needs the freeze commit.
if [[ -z "$base" ]]; then
  [[ $findings -eq 0 ]] && { echo "TAMPER: CLEAN (not frozen yet — freeze-relative checks skipped)"; exit 0; }
  echo "TAMPER: FAIL ($findings findings)"; exit 1
fi
if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  report "freeze commit $base is not in local history (shallow clone? fetch full history, e.g. fetch-depth: 0)"
  echo "TAMPER: FAIL ($findings findings)"; exit 1
fi

# 3a. Frozen criteria.
if [[ -f "$FD/LEDGER.lock" && -f "$FD/ledger.json" ]]; then
  [[ "$(fl_criteria_hash "$FD/ledger.json")" == "$(tr -d '[:space:]' < "$FD/LEDGER.lock")" ]] \
    || report "ledger criteria changed since freeze (hash differs from .finish/LEDGER.lock)"
fi

diffargs=(-M --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$base")

# 3b. Deleted tests (renames to another test path are fine).
while IFS=$'\t' read -r st a b; do
  case "$st" in
    D*)
      if fl_is_protected_path "$a"; then
        survivor="$(all_files | grep -E "$FL_PROTECTED_RE" | grep -F "/$(basename "$a")" || true)"
        [[ -n "$survivor" ]] || report "protected test deleted: $a"
      elif fl_is_test_path "$a"; then
        report "test file deleted: $a"
      fi ;;
    R*)
      if { fl_is_protected_path "$a" && ! fl_is_protected_path "$b"; } || { fl_is_test_path "$a" && ! fl_is_test_path "$b"; }; then
        report "test file renamed out of the test tree: $a → $b"
      fi ;;
  esac
done < <(git diff --name-status "${diffargs[@]}" 2>/dev/null)

# 3c. Added markers in tests, and filter changes in test configs.
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if fl_is_test_path "$f" && ! fl_is_protected_path "$f"; then
    git diff -U0 "${diffargs[@]}" -- "$f" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+ ' | grep -E "$MARKER_RE" \
      | while IFS= read -r l; do printf '%s\n' "test marker added in $f: ${l#+}"; done
  fi
  if printf '%s\n' "$f" | grep -Eq "$CONFIG_PATH_RE"; then
    git diff -U0 "${diffargs[@]}" -- "$f" 2>/dev/null | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | grep -E "$CONFIG_KEY_RE" \
      | while IFS= read -r l; do printf '%s\n' "test config filter changed in $f: $l"; done
  fi
done < <(git diff --name-only "${diffargs[@]}" 2>/dev/null) > "$TMP"
flush

# 3d. verify.sh stages.
stage_val() { local v="${1#*=}"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; printf '%s' "$v"; }
if git cat-file -e "$base:.finish/verify.sh" 2>/dev/null; then
  while IFS= read -r line; do
    name="${line%%=*}"
    old="$(stage_val "$line")"
    cur_line="$(grep -E "^${name}=" .finish/verify.sh 2>/dev/null | head -1 || true)"
    cur="$(stage_val "$cur_line")"
    case "$old" in ""|n/a*) [[ "$name" == "STAGE_TAMPER" ]] || continue ;; esac
    if [[ -z "$cur_line" ]]; then
      report "verify.sh: $name removed"
    elif [[ "$cur" == n/a* ]]; then
      report "verify.sh: $name changed to \"$cur\" after freeze"
    elif [[ "$name" == "STAGE_TAMPER" && "$cur" != "$old" ]]; then
      report "verify.sh: STAGE_TAMPER changed from \"$old\" to \"$cur\""
    fi
  done < <(git show "$base:.finish/verify.sh" | grep -E '^STAGE_[A-Z0-9_]+=')
fi

# 3e. Vendored scripts.
changed_bin="$(git diff --name-only "${diffargs[@]}" -- .finish/bin 2>/dev/null)"
[[ -z "$changed_bin" ]] || report "vendored scripts changed since freeze: $(printf '%s' "$changed_bin" | tr '\n' ' ')"

if [[ $findings -eq 0 ]]; then
  echo "TAMPER: CLEAN"
  exit 0
fi
echo "TAMPER: FAIL ($findings findings)"
exit 1
