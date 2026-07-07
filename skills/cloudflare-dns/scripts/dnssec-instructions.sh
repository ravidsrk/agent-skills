#!/bin/bash
# Print the manual steps required to complete DNSSEC at Namecheap.
# Usage: ./dnssec-instructions.sh <domain>
#
# Reads the saved DNSSEC details from .dns-state/<domain>/dnssec.json
# and shows the exact values to paste into Namecheap's DS record form.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain>"; exit 1; }
DIR="$(state_dir "$DOMAIN")"

if [ ! -f "${DIR}/dnssec.json" ]; then
  echo "ERROR: no dnssec.json found. Run harden.sh first." >&2
  exit 1
fi

DNSSEC_FILE="${DIR}/dnssec.json" DOM="$DOMAIN" python3 - <<'PYEOF'
import json, os
d = json.load(open(os.environ['DNSSEC_FILE']))
domain = os.environ['DOM']

ALG = {
    1: 'RSAMD5',
    5: 'RSASHA1',
    7: 'RSASHA1-NSEC3-SHA1',
    8: 'RSASHA256',
    10: 'RSASHA512',
    13: 'ECDSAP256SHA256',
    14: 'ECDSAP384SHA384',
    15: 'ED25519',
    16: 'ED448',
}
DTYPE = {1: 'SHA-1', 2: 'SHA-256', 4: 'SHA-384'}

try:
    alg_n = int(d.get('algorithm') or 0)
except Exception:
    alg_n = 0
try:
    dt_n = int(d.get('digest_type') or 0)
except Exception:
    dt_n = 0

print("===============================================================")
print("  DNSSEC — Manual step at Namecheap (one-time per domain)")
print("===============================================================")
print()
print(f"Domain: {domain}")
print()
print("1. Open: https://ap.www.namecheap.com/domains/list/")
print(f"2. Click 'Manage' next to {domain}")
print("3. Go to the 'Advanced DNS' tab")
print("4. Find the 'DNSSEC' toggle — turn it ON")
print("5. Click 'Add new record', then enter EXACTLY these values:")
print()
print(f"     Key Tag      : {d.get('key_tag')}")
print(f"     Algorithm    : {alg_n}  ({ALG.get(alg_n, 'unknown')})")
print(f"     Digest Type  : {dt_n}   ({DTYPE.get(dt_n, 'unknown')})")
print(f"     Digest       : {d.get('digest')}")
print()
print("6. Click the checkmark to save.")
print()
print("After saving, propagation takes ~60 minutes. Verify with:")
print(f"  curl -sH 'accept: application/dns-json' \\")
print(f"    'https://1.1.1.1/dns-query?name={domain}&type=DS' | python3 -m json.tool")
print()
print("Then check the chain of trust at:")
print(f"  https://dnsviz.net/d/{domain}/dnssec/")
print(f"  https://dnssec-analyzer.verisignlabs.com/{domain}")
print()
print("===============================================================")
print()
print("Alternative: full DS record string (copy as one line):")
print(f"  {domain}. 3600 IN DS {d.get('key_tag')} {alg_n} {dt_n} {d.get('digest')}")
print()
PYEOF
