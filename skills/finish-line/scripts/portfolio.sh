#!/usr/bin/env bash
# portfolio.sh — free, offline snapshot of every git repo under a folder, so you
# can see the graveyard before spending compute on a full triage.
#
#   portfolio.sh [dir]        default: current directory; scans dir/* one level deep
#
# Columns: repo · last commit · commits · docs (*.md under docs/, specs/, prd*) ·
# stub markers (TODO/FIXME/placeholder/lorem/mock data/not implemented/coming soon)
# · Finish Line status and P0 progress if .finish/ exists.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;; esac
DIR="${1:-$PWD}"
[[ -d "$DIR" ]] || { echo "no such directory: $DIR"; exit 1; }

STUB_RE='TODO|FIXME|XXX|HACK|placeholder|lorem ipsum|mock(ed)?Data|not implemented|NotImplemented|coming soon'
EXCLUDES='node_modules|\.git/|/dist/|/build/|/\.next/|/vendor/|/Pods/|\.lock$|-lock\.json$|\.min\.js$|/\.finish/|/\.claude/'

count_stubs() {
  if command -v rg >/dev/null 2>&1; then
    rg -i -c -e "$STUB_RE" "$1" -g '!*.lock' -g '!*-lock.json' -g '!*.min.js' -g '!.finish' 2>/dev/null \
      | awk -F: '{ s += $NF } END { print s + 0 }'
  else
    grep -rIEic "$STUB_RE" "$1" 2>/dev/null | grep -vE "$EXCLUDES" | awk -F: '{ s += $NF } END { print s + 0 }'
  fi
}

rows=""
for repo in "$DIR"/*/; do
  repo="${repo%/}"
  [[ -d "$repo/.git" || -f "$repo/.git" ]] || continue
  name="$(basename "$repo")"
  ts="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
  when="$(git -C "$repo" log -1 --format=%cr 2>/dev/null || echo never)"
  commits="$(git -C "$repo" rev-list --count HEAD 2>/dev/null || echo 0)"
  docs="$(find -H "$repo" -path "$repo/node_modules" -prune -o -type f -iname '*.md' \( -ipath '*/docs/*' -o -ipath '*/specs/*' -o -iname 'prd*' -o -iname '*spec*.md' \) -print 2>/dev/null | wc -l | tr -d ' ')"
  stubs="$(count_stubs "$repo")"
  fin="—"
  if [[ -f "$repo/.finish/STATUS" ]]; then
    fin="$(tr -d '[:space:]' < "$repo/.finish/STATUS")"
    if [[ -f "$repo/.finish/ledger.json" ]]; then
      fin="$fin $(jq -r '[.items[] | select(.priority == "P0")] | "P0 \(map(select(.status == "passing")) | length)/\(length)"' "$repo/.finish/ledger.json" 2>/dev/null)"
    fi
  fi
  rows="$rows$ts|$name|$when|$commits|$docs|$stubs|$fin
"
done

[[ -n "$rows" ]] || { echo "no git repos directly under $DIR"; exit 0; }
echo "| Repo | Last commit | Commits | Docs | Stub markers | Finish Line |"
echo "|---|---|---|---|---|---|"
printf '%s' "$rows" | sort -t'|' -k1,1nr | while IFS='|' read -r _ name when commits docs stubs fin; do
  echo "| $name | $when | $commits | $docs | $stubs | $fin |"
done
echo
echo "Next: run the triage prompt in $(cd "$HERE/.." && pwd)/references/portfolio-triage.md to pick exactly one FINISH-NEXT."
