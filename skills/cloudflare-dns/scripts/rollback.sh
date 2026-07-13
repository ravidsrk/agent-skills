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
REQUIRE_NAMECHEAP=1 require_env

read -r SLD TLD <<< "$(domain_split "$DOMAIN")"
DIR="$(state_dir "$DOMAIN")"

echo "▸ Rolling back nameservers for $DOMAIN"

if [ -f "${DIR}/audit-pre.json" ]; then
  ORIGINAL_NS=$(python3 -c "
import json
data = json.load(open('${DIR}/audit-pre.json'))
print(' '.join(data['nameservers']))")
  echo "  restoring original nameservers:"
  for ns in $ORIGINAL_NS; do echo "    → $ns"; done
  echo ""
  resp=$(nc_set_nameservers "$SLD" "$TLD" $ORIGINAL_NS)
else
  echo "  no baseline — using Namecheap BasicDNS default"
  resp=$(nc_reset_nameservers "$SLD" "$TLD")
fi

echo "$resp" > "${DIR}/rollback.log"
if echo "$resp" | grep -q 'Status="OK"'; then
  echo "  🟢 rollback applied"
else
  echo "  🔴 Namecheap error — see ${DIR}/rollback.log" >&2
  exit 1
fi
