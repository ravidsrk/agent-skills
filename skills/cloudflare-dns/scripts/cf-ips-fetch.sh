#!/bin/bash
# Fetch current Cloudflare IP ranges and save as a JSON file your apps can consume.
# Usage: ./cf-ips-fetch.sh [--output=<path>]
#
# Run this on a schedule (weekly cron) to keep the allowlist fresh.
# Cloudflare publishes their ranges at:
#   https://www.cloudflare.com/ips-v4
#   https://www.cloudflare.com/ips-v6
#
# Safety:
#   - Uses -sSf so any HTTP error (5xx / redirects to an error page) aborts.
#   - Validates each line looks like a CIDR before writing.
#   - Writes atomically via temp-file + mv so a partial failure never clobbers
#     a working file mid-run.

set -euo pipefail

OUTPUT=".dns-state/_shared/cloudflare-ips.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --output=*) OUTPUT="${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

OUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUT_DIR"

# Fetch; -sSf fails on HTTP errors instead of silently succeeding with an error body.
V4_RAW=$(curl -sSf https://www.cloudflare.com/ips-v4)
V6_RAW=$(curl -sSf https://www.cloudflare.com/ips-v6)

# Validate each line is a CIDR. Refuse to write garbage.
V4_VALID=$(V4="$V4_RAW" python3 -c "
import os, re, sys, ipaddress
raw = os.environ['V4'].splitlines()
out = []
for line in raw:
    l = line.strip()
    if not l: continue
    try:
        net = ipaddress.IPv4Network(l, strict=False)
        out.append(str(net))
    except Exception:
        pass
if not out:
    sys.exit('no valid IPv4 CIDRs in response')
print('\n'.join(sorted(out, key=lambda s: ipaddress.IPv4Network(s))))
")

V6_VALID=$(V6="$V6_RAW" python3 -c "
import os, sys, ipaddress
raw = os.environ['V6'].splitlines()
out = []
for line in raw:
    l = line.strip()
    if not l: continue
    try:
        net = ipaddress.IPv6Network(l, strict=False)
        out.append(str(net))
    except Exception:
        pass
if not out:
    sys.exit('no valid IPv6 CIDRs in response')
print('\n'.join(sorted(out, key=lambda s: ipaddress.IPv6Network(s))))
")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Compose JSON via python (no shell string interp of user data)
TMP="$(mktemp "${OUT_DIR}/.cloudflare-ips.XXXXXX.json")"
trap 'rm -f "$TMP"' EXIT

V4_LIST="$V4_VALID" V6_LIST="$V6_VALID" NOW_ENV="$NOW" python3 -c "
import json, os
out = {
    'v4': [l for l in os.environ['V4_LIST'].split('\n') if l],
    'v6': [l for l in os.environ['V6_LIST'].split('\n') if l],
    'updated': os.environ['NOW_ENV'],
    'source': {
        'v4': 'https://www.cloudflare.com/ips-v4',
        'v6': 'https://www.cloudflare.com/ips-v6',
    },
}
print(json.dumps(out, indent=2))
" > "$TMP"

# Atomic swap into place.
mv "$TMP" "$OUTPUT"
trap - EXIT

V4_COUNT=$(printf '%s\n' "$V4_VALID" | grep -c . || true)
V6_COUNT=$(printf '%s\n' "$V6_VALID" | grep -c . || true)

echo "(OK) Cloudflare IPs fetched and saved"
echo "   $V4_COUNT IPv4 ranges + $V6_COUNT IPv6 ranges"
echo "   -> $OUTPUT"
echo ""
echo "Use in your app middleware:"
echo "   const cf = JSON.parse(fs.readFileSync('$OUTPUT', 'utf8'));"
echo "   const allow = [...cf.v4, ...cf.v6];"
