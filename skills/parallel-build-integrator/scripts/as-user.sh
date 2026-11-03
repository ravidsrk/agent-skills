#!/usr/bin/env bash
# Run a command as a non-root user, the way CI runs it, keeping this shell's environment. The environment is passed
# as runuser's own, never on its command line, where any local user could read it in /proc/<pid>/cmdline.
#
# Usage: as-user.sh <user> <command> [args...]
#   e.g. as-user.sh nobody pnpm exec vitest run apps/cli/src/sea-prelude.test.ts
set -euo pipefail

user="${1:?usage: as-user.sh <user> <command> [args...]}"; shift
[ $# -gt 0 ] || { echo "no command" >&2; exit 2; }
if [ "$(id -u)" != 0 ]; then
  echo "as-user.sh: already non-root ($(id -un)); running directly" >&2
  exec "$@"
fi
runuser=$(command -v runuser || true)
[ -n "$runuser" ] || { echo "as-user.sh: runuser not found" >&2; exit 1; }
# The user must be able to reach this directory; root-only scratch paths (mode 0700) are the usual failure.
if ! "$runuser" -u "$user" -- test -r "$PWD" -a -x "$PWD"; then
  echo "as-user.sh: $user cannot read $PWD; copy the work to a directory it can reach (e.g. under /tmp, mode 755)" >&2
  exit 1
fi
exec "$runuser" --preserve-environment -u "$user" -- "$@"
