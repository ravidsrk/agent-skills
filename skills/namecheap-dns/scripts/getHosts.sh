#!/usr/bin/env bash
# getHosts.sh — list Namecheap DNS records for a domain.
#
# Usage:
#   ./getHosts.sh <sld> <tld>            # XML (default)
#   ./getHosts.sh <sld> <tld> --json     # JSON array on stdout
#
# Env: NAMECHEAP_API_KEY, NAMECHEAP_API_USER
# Optional: NAMECHEAP_CLIENT_IP, NAMECHEAP_API_BASE
set -euo pipefail

SLD="${1:?usage: getHosts.sh <sld> <tld> [--json]}"
TLD="${2:?usage: getHosts.sh <sld> <tld> [--json]}"
FORMAT="${3:-}"

: "${NAMECHEAP_API_KEY:?set NAMECHEAP_API_KEY}"
: "${NAMECHEAP_API_USER:?set NAMECHEAP_API_USER}"

API_BASE="${NAMECHEAP_API_BASE:-https://api.namecheap.com/xml.response}"
CLIENT_IP="${NAMECHEAP_CLIENT_IP:-$(curl -sS https://api.ipify.org)}"

RESP="$(curl -sS -G "$API_BASE" \
  --data-urlencode "ApiUser=$NAMECHEAP_API_USER" \
  --data-urlencode "ApiKey=$NAMECHEAP_API_KEY" \
  --data-urlencode "UserName=$NAMECHEAP_API_USER" \
  --data-urlencode "ClientIp=$CLIENT_IP" \
  --data-urlencode "Command=namecheap.domains.dns.getHosts" \
  --data-urlencode "SLD=$SLD" \
  --data-urlencode "TLD=$TLD")"

if echo "$RESP" | grep -q '1011150'; then
  echo "getHosts: ERROR 1011150 Invalid request IP — whitelist ${CLIENT_IP}" >&2
  exit 2
fi

if [ "$FORMAT" = "--json" ]; then
  printf '%s' "$RESP" | python3 -c '
import re, json, sys
xml = sys.stdin.read()
hosts = []
for m in re.finditer(r"<host\s+([^>]+?)/?>", xml, flags=re.I):
    attrs = dict(re.findall(r"(\w+)=\"([^\"]*)\"", m.group(1)))
    hosts.append({
        "name": attrs.get("Name", ""),
        "type": attrs.get("Type", ""),
        "address": attrs.get("Address", ""),
        "ttl": attrs.get("TTL", "300"),
        "mxpref": attrs.get("MXPref", "10"),
        "hostId": attrs.get("HostId", ""),
    })
print(json.dumps(hosts, indent=2))
'
else
  echo "$RESP"
fi
