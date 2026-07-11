#!/usr/bin/env bash
# setHosts.sh — wholesale-safe Namecheap DNS update.
#
# Usage:
#   cat records.json | ./setHosts.sh <sld> <tld>
#
# records.json: array of objects
#   [{"name":"@","type":"A","address":"1.2.3.4","ttl":"300","mxpref":"10"}, ...]
#
# Env (required):
#   NAMECHEAP_API_KEY
#   NAMECHEAP_API_USER   # Namecheap account username (ApiUser + UserName)
#
# Optional:
#   NAMECHEAP_CLIENT_IP  # defaults to curl https://api.ipify.org
#   NAMECHEAP_EMAIL_TYPE # FWD (default) or MX
#   NAMECHEAP_API_BASE   # default https://api.namecheap.com/xml.response
#
# Safety: this REPLACES every host record. Pass the FULL desired set.
set -euo pipefail

SLD="${1:?usage: setHosts.sh <sld> <tld> < records.json}"
TLD="${2:?usage: setHosts.sh <sld> <tld> < records.json}"

: "${NAMECHEAP_API_KEY:?set NAMECHEAP_API_KEY}"
: "${NAMECHEAP_API_USER:?set NAMECHEAP_API_USER}"

API_BASE="${NAMECHEAP_API_BASE:-https://api.namecheap.com/xml.response}"
EMAIL_TYPE="${NAMECHEAP_EMAIL_TYPE:-FWD}"
CLIENT_IP="${NAMECHEAP_CLIENT_IP:-$(curl -sS https://api.ipify.org)}"

JSON="$(cat)"
if [ -z "$JSON" ]; then
  echo "ERROR: empty stdin — pass a JSON array of records" >&2
  exit 1
fi

ARGS_FILE="$(mktemp)"
trap 'rm -f "$ARGS_FILE"' EXIT

printf '%s' "$JSON" | python3 -c '
import json, sys
sld, tld, email_type, client_ip, user, key = sys.argv[1:7]
records = json.load(sys.stdin)
if not isinstance(records, list) or not records:
    sys.stderr.write("ERROR: records.json must be a non-empty JSON array\n")
    sys.exit(1)

params = [
    ("ApiUser", user),
    ("ApiKey", key),
    ("UserName", user),
    ("ClientIp", client_ip),
    ("Command", "namecheap.domains.dns.setHosts"),
    ("SLD", sld),
    ("TLD", tld),
    ("EmailType", email_type),
]

for i, rec in enumerate(records, start=1):
    name = rec.get("name") or rec.get("Name") or rec.get("HostName")
    rtype = rec.get("type") or rec.get("Type") or rec.get("RecordType")
    address = rec.get("address") or rec.get("Address")
    ttl = str(rec.get("ttl") or rec.get("TTL") or "300")
    mxpref = str(rec.get("mxpref") or rec.get("MXPref") or rec.get("mxPref") or "10")
    if not name or not rtype or address is None:
        sys.stderr.write(f"ERROR: record {i} needs name, type, address\n")
        sys.exit(1)
    params.append((f"HostName{i}", str(name)))
    params.append((f"RecordType{i}", str(rtype)))
    params.append((f"Address{i}", str(address)))
    params.append((f"TTL{i}", ttl))
    if str(rtype).upper() == "MX":
        params.append((f"MXPref{i}", mxpref))

for k, v in params:
    print(f"{k}\t{v}")
' "$SLD" "$TLD" "$EMAIL_TYPE" "$CLIENT_IP" "$NAMECHEAP_API_USER" "$NAMECHEAP_API_KEY" >"$ARGS_FILE"

CURL_ARGS=()
while IFS=$'\t' read -r k v; do
  CURL_ARGS+=(--data-urlencode "${k}=${v}")
done <"$ARGS_FILE"

echo "setHosts: ${SLD}.${TLD} from IP ${CLIENT_IP}..." >&2
RESP="$(curl -sS -G "$API_BASE" "${CURL_ARGS[@]}")"
echo "$RESP"

if echo "$RESP" | grep -q 'Status="OK"'; then
  if echo "$RESP" | grep -qi 'IsSuccess="true"'; then
    echo "setHosts: OK" >&2
    exit 0
  fi
fi
if echo "$RESP" | grep -q '1011150'; then
  echo "setHosts: ERROR 1011150 Invalid request IP — whitelist ${CLIENT_IP} at Namecheap → API Access" >&2
  exit 2
fi
echo "setHosts: FAILED — see XML response above" >&2
exit 1
