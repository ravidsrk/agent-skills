#!/usr/bin/env bash
# Scan the lines added since <base> for anything secret-shaped. Prints file, line and a redacted match; exits 1 if
# any match survives KEYSCAN_ALLOW (an ERE from .integrator/config.sh, matched against the whole added line).
#
# Usage: keyscan.sh <base-ref> [worktree]
set -uo pipefail
. "$(dirname "$0")/lib.sh"

base="${1:?usage: keyscan.sh <base-ref> [worktree]}"
wt="$(cd "${2:-.}" && pwd)"
load_config "$wt" >/dev/null 2>&1 || KEYSCAN_ALLOW=""
cd "$wt"

# Provider key prefixes, private keys, cloud and chat tokens. Extend for your vendors.
PATTERN='sk-ant-[A-Za-z0-9_-]{8,}|sk-proj-[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9]{32,}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{20,}|gh[ousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|glpat-[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{30,}'

hits=$(git diff --unified=0 "$base"...HEAD | awk '
  /^\+\+\+ b\// { file = substr($0, 7); next }
  /^@@/ { split($3, a, ","); line = substr(a[1], 2) - 1; next }
  /^\+/ { line++; print file ":" line ":" substr($0, 2) }
' | grep -E "$PATTERN" || true)
if [ -n "$KEYSCAN_ALLOW" ] && [ -n "$hits" ]; then
  hits=$(printf '%s\n' "$hits" | grep -Ev "$KEYSCAN_ALLOW" || true)
fi

if [ -z "$hits" ]; then
  echo "keyscan: no secret-shaped additions since $base"
  exit 0
fi
printf '%s\n' "$hits" | sed -E 's/(sk-ant-|sk-proj-|sk-|ghp_|github_pat_|gh[ousr]_|AKIA|ASIA|xox[baprs]-|AIza|glpat-|npm_)([A-Za-z0-9_-]{4})[A-Za-z0-9_-]*/\1\2…/g' | cut -c1-220
echo "keyscan: $(printf '%s\n' "$hits" | wc -l) match(es). Inspect each: a placeholder can go in KEYSCAN_ALLOW; anything real stops the push."
exit 1
