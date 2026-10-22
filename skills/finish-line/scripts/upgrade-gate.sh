#!/usr/bin/env bash
# upgrade-gate.sh — checked migration of the shipped legacy spec selector.
# Run inside the product repo, with all runners/sessions stopped:
#   upgrade-gate.sh --check     read-only distribution compatibility check
#   upgrade-gate.sh --propose   print the gate with only the known selector repaired
#   upgrade-gate.sh --apply     install that repair before the freeze only
# Unknown/custom selector logic needs a reviewed manual merge. Frozen proposals
# require the existing gate amendment/rebaseline review; they never authorize a
# bin refresh. Frozen bin drift requires a separately sanctioned migration or
# an explicit archived fresh run. This helper never writes bin or freeze markers.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need git awk cmp
[[ $# -eq 1 ]] || fl_die "usage: upgrade-gate.sh --check|--propose|--apply"
mode="$1"
case "$mode" in --check|--propose|--apply) ;; *) fl_die "unknown upgrade-gate.sh option: $mode" ;; esac
cd "$(fl_root)" || exit 2
FD=.finish; gate="$FD/verify.sh"
[[ ! -L "$FD" ]] || fl_die "upgrade-gate.sh refuses a symlink .finish directory"
frozen() { [[ -e "$FD/FREEZE" || -L "$FD/FREEZE" || -e "$FD/LEDGER.lock" || -L "$FD/LEDGER.lock" ]]; }
if [[ "$mode" == --check ]]; then
  [[ ! -L "$FD/bin" && ( ! -e "$FD/bin" || -d "$FD/bin" ) ]] || fl_die "upgrade-gate.sh refuses a non-directory/symlink bin path"
  for s in lib.sh ledger.sh tamper.sh; do
    [[ ! -L "$FD/bin/$s" && ( ! -e "$FD/bin/$s" || -f "$FD/bin/$s" ) ]] || fl_die "upgrade-gate.sh refuses a non-regular/symlink bin script: $s"
  done
fi
if [[ ! -e "$gate" && ! -L "$gate" ]]; then
  if [[ "$mode" == --check ]] && ! frozen; then exit 0; fi
  fl_die "upgrade-gate.sh requires a readable regular gate; frozen missing gates cannot be refreshed"
fi
[[ -f "$gate" && -r "$gate" && ! -L "$gate" ]] || fl_die "upgrade-gate.sh requires a readable non-symlink regular gate"
[[ -s "$gate" && -z "$(tail -c1 "$gate")" ]] || fl_die "upgrade-gate.sh requires a newline-terminated text gate"
LC_ALL=C tr -d '\000' < "$gate" | cmp -s "$gate" - || fl_die "upgrade-gate.sh refuses NUL bytes in the text gate"
bash -n "$gate" || fl_die "upgrade-gate.sh refuses a gate with shell syntax errors"

# Match the shipped function and adjacent selector/empty branch, not an isolated
# assignment or marker comment. Commands, stage lists and other bytes stay intact.
kind="$(awk '
function matches(start, seq, n, i) {
  for (i=1; i<=n; i++) if (a[start+i-1] != seq[i]) return 0
  return 1
}
BEGIN {
  f[1]="specs_for() { # stage → spec paths from the ledger (in-scope; --passing in quick mode)"
  f[2]="  local method"
  f[3]="  case \"$1\" in E2E_WEB) method=e2e-web ;; E2E_MOBILE) method=e2e-mobile ;; API) method=api ;; *) return 0 ;; esac"
  f[4]="  [[ -f .finish/ledger.json ]] || return 0"
  f[5]="  # shellcheck disable=SC2086"
  f[6]="  ./.finish/bin/ledger.sh specs $passing_flag --method \"$method\""
  f[7]="}"
  old[1]="    E2E_WEB|E2E_MOBILE|API)"
  old[2]="      specs=\"$(specs_for \"$s\")\""
  old[3]="      if [[ -z \"$specs\" ]]; then line \"$s\" SKIP 0 \"no specs yet\"; continue; fi"
  new[1]=old[1]
  new[2]="      if ! specs=\"$(specs_for \"$s\")\"; then"
  new[3]="        line \"$s\" FAIL 0 \"could not select valid ledger specs\""
  new[4]="        echo \"GATE: FAIL at $s\" | tee -a \"$summary\"; exit 1"
  new[5]="      fi"
  new[6]=old[3]
}
{ a[NR]=$0; if (index($0,"specs_for")) calls++ }
END {
  for (j=1; j<=NR; j++) {
    if (matches(j,f,7)) functions++
    if (matches(j,old,3)) legacy++
    if (matches(j,new,6)) current++
  }
  if (calls != 2 || functions != 1) exit 2
  if (legacy == 1 && current == 0) print "legacy"
  else if (current == 1 && legacy == 0) print "current"
  else exit 2
}' "$gate")" || fl_die "upgrade-gate.sh cannot recognize this custom selector; preserve the gate and review a manual merge"

if [[ "$mode" == --check ]]; then
  [[ "$kind" == current ]] || fl_die "legacy gate ignores selector failure; run upgrade-gate.sh --propose and review the exact repair before distributing new bin"
  if frozen; then
    for s in lib.sh ledger.sh tamper.sh; do
      [[ -f "$FD/bin/$s" && ! -L "$FD/bin/$s" ]] && cmp -s "$HERE/$s" "$FD/bin/$s" \
        || fl_die "frozen bin drift ($s): no automatic refresh/reanchor; use a separately sanctioned migration or explicit archived fresh run"
    done
  fi
  exit 0
fi

propose() {
  if [[ "$kind" == current ]]; then cat "$gate"
  else
    awk '
      $0 == "      specs=\"$(specs_for \"$s\")\"" {
        print "      if ! specs=\"$(specs_for \"$s\")\"; then"
        print "        line \"$s\" FAIL 0 \"could not select valid ledger specs\""
        print "        echo \"GATE: FAIL at $s\" | tee -a \"$summary\"; exit 1"
        print "      fi"
        next
      }
      { print }
    ' "$gate"
  fi
}
[[ "$mode" != --propose ]] || { propose; exit $?; }
frozen && fl_die "frozen gate: --apply refused; --propose is read-only for the existing reviewed amend --rebaseline process (not bin authorization)"
[[ "$kind" != current ]] || { echo "gate selector already current"; exit 0; }
[[ ! -e "$(git rev-parse --git-dir)/finish-line.lock" ]] || fl_die "runner active or lock occupied; stop runners before gate migration"
upgrade_lock="$FD/.gate-upgrade.lock"
mkdir "$upgrade_lock" 2>/dev/null || fl_die "gate migration already active or lock occupied; stop all runners and inspect $upgrade_lock"
snapshot=""; candidate=""
trap 'rm -f "$snapshot" "$candidate"; rmdir "$upgrade_lock" 2>/dev/null' EXIT
snapshot="$(mktemp "$FD/.verify-before.XXXXXX")" || fl_die "could not stage original gate"
candidate="$(mktemp "$FD/.verify-upgrade.XXXXXX")" || fl_die "could not stage repaired gate"
cp -p "$gate" "$snapshot" && cp -p "$gate" "$candidate" || fl_die "could not preserve gate bytes/mode"
propose > "$candidate" || fl_die "could not write repaired gate"
bash -n "$candidate" || fl_die "repaired gate has shell syntax errors"
! frozen && [[ ! -L "$gate" ]] && cmp -s "$gate" "$snapshot" \
  || fl_die "gate or freeze markers changed during migration; no repair installed"
mv "$candidate" "$gate" || fl_die "could not install repaired gate"
echo "gate selector repaired; every other gate byte and mode preserved; review and run the configured gate"
