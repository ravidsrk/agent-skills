#!/bin/bash
# Fetch current Cloudflare IP ranges and save as a JSON file your apps can consume.
# Usage: ./cf-ips-fetch.sh [--output=<path>]
#
# Run this on a schedule (weekly cron) to keep the allowlist fresh.
# Cloudflare publishes their ranges at:
#   https://www.cloudflare.com/ips-v4
#   https://www.cloudflare.com/ips-v6

set -euo pipefail

OUTPUT=".dns-state/_shared/cloudflare-ips.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --output=*) OUTPUT="${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

mkdir -p "$(dirname "$OUTPUT")"

V4=$(curl -sS https://www.cloudflare.com/ips-v4 | grep -v '^$' | sort -V)
V6=$(curl -sS https://www.cloudflare.com/ips-v6 | grep -v '^$' | sort -V)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

V4_JSON=$(echo "$V4"  | python3 -c "import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))")
V6_JSON=$(echo "$V6"  | python3 -c "import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))")

python3 -c "
import json
out = {
  'v4': $V4_JSON,
  'v6': $V6_JSON,
  'updated': '$NOW',
  'source': {
    'v4': 'https://www.cloudflare.com/ips-v4',
    'v6': 'https://www.cloudflare.com/ips-v6'
  }
}
print(json.dumps(out, indent=2))
" > "$OUTPUT"

V4_COUNT=$(echo "$V4" | wc -l)
V6_COUNT=$(echo "$V6" | wc -l)

echo "🟢 Cloudflare IPs fetched and saved"
echo "   $V4_COUNT IPv4 ranges + $V6_COUNT IPv6 ranges"
echo "   → $OUTPUT"
echo ""
echo "Use in your app middleware:"
echo "   const cf = JSON.parse(fs.readFileSync('$OUTPUT', 'utf8'));"
echo "   const allow = [...cf.v4, ...cf.v6];"
