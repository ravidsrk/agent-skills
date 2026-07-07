#!/bin/bash
# Roll back nameservers from Cloudflare → Namecheap default (or saved baseline).
# Usage: ./rollback.sh <domain>
#
# Reads the original nameservers from .dns-state/<domain>/audit-pre.json
# and restores them at Namecheap. Falls back to BasicDNS if no baseline.
#
# The Cloudflare zone is left intact — re-running migrate.sh ... flip will
# redo the cutover without re-importing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain>"; exit 1; }
require_env NAMECHEAP_API_KEY NAMECHEAP_API_USER

read -r SLD TLD <<< "$(domain_split "$DOMAIN")"
DIR="$(state_dir "$DOMAIN")"

echo "-- Rolling back nameservers for $DOMAIN"

if [ -f "${DIR}/audit-pre.json" ]; then
  # Re-validate baseline before trusting it. An empty/malformed NS list
  # would ship an empty Nameservers= param and either be rejected or
  # (worse) accepted, wrecking DNS during a live rollback.
  BASELINE_NS=$(DIR_ENV="$DIR" python3 - <<'PYEOF'
import json, os, sys
try:
    data = json.load(open(os.path.join(os.environ['DIR_ENV'], 'audit-pre.json')))
except Exception as e:
    print(f'BASELINE_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
ns = [n.strip() for n in (data.get('nameservers') or []) if n and n.strip()]
if not ns:
    print('BASELINE_EMPTY', file=sys.stderr)
    sys.exit(2)
print(' '.join(ns))
PYEOF
)
  RC=$?
  if [ $RC -ne 0 ] || [ -z "${BASELINE_NS// /}" ]; then
    echo "  ERROR: audit-pre.json baseline is missing/empty NS list — refusing to rollback with empty Nameservers" >&2
    echo "         Delete the baseline and re-run: scripts/audit.sh $DOMAIN" >&2
    exit 1
  fi
  echo "  restoring original nameservers:"
  # shellcheck disable=SC2086
  for ns in $BASELINE_NS; do echo "    -> $ns"; done
  echo ""
  # shellcheck disable=SC2086
  resp=$(nc_set_nameservers "$SLD" "$TLD" $BASELINE_NS)
else
  echo "  no baseline — using Namecheap BasicDNS default"
  resp=$(nc_reset_nameservers "$SLD" "$TLD")
fi

echo "$resp" > "${DIR}/rollback.log"
if echo "$resp" | grep -q 'Status="OK"'; then
  echo "  (OK) rollback applied"
  echo "  Note: public resolvers may cache Cloudflare NS for up to 30 min. Verify with:"
  echo "    curl -sH 'accept: application/dns-json' 'https://1.1.1.1/dns-query?name=${DOMAIN}&type=NS' | python3 -m json.tool"
else
  echo "  Namecheap error — see ${DIR}/rollback.log" >&2
  exit 1
fi
