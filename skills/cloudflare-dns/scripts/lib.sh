#!/bin/bash
# Shared helpers for cloudflare-dns scripts.
# Source this from the other scripts via: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# --- env validation ------------------------------------------------------

require_env() {
  local missing=()
  [ -n "${CLOUDFLARE_API_KEY:-}" ]        || missing+=("CLOUDFLARE_API_KEY")
  [ -n "${NAMECHEAP_API_KEY:-}" ]         || missing+=("NAMECHEAP_API_KEY")

  # Global key + email only required for zone creation
  if [ "${REQUIRE_GLOBAL_KEY:-0}" = "1" ]; then
    [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] || missing+=("CLOUDFLARE_GLOBAL_API_KEY")
    [ -n "${CLOUDFLARE_EMAIL:-}" ]          || missing+=("CLOUDFLARE_EMAIL")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "ERROR: missing env vars: ${missing[*]}" >&2
    exit 1
  fi
}

# --- state directory -----------------------------------------------------

state_dir() {
  local domain="$1"
  local d=".dns-state/${domain}"
  mkdir -p "$d"
  echo "$d"
}

# --- Cloudflare API wrappers --------------------------------------------

# cf_api <method> <path> [<body-json>]
# Tries ACCOUNT TOKEN first (Bearer). On `Authentication error` (code 10000)
# falls back to GLOBAL KEY automatically. This handles the common case where
# the account token's zone-resource binding doesn't yet include a newly-
# created zone — the token can list zones but can't read records inside them.
cf_api() {
  local method="$1" path="$2" body="${3:-}"
  local resp
  if [ -n "$body" ]; then
    resp=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}" \
      -H "Content-Type: application/json" \
      --data "$body")
  else
    resp=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "Authorization: Bearer ${CLOUDFLARE_API_KEY}")
  fi

  # On account-token auth failure, fall back to global key if available.
  local needs_fallback
  needs_fallback=$(echo "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    errs = d.get('errors') or []
    fail = (not d.get('success')) and any(
        e.get('code') in (10000, 9109, 6003) for e in errs
    )
    print('1' if fail else '0')
except Exception:
    print('0')
")
  if [ "$needs_fallback" = "1" ] && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
    if [ -n "$body" ]; then
      resp=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
        -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
        -H "Content-Type: application/json" \
        --data "$body")
    else
      resp=$(curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
        -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}")
    fi
  fi
  printf '%s' "$resp"
}

# cf_global <method> <path> [<body-json>]  — uses GLOBAL KEY (email + key)
# Use only for zone creation. Always sets REQUIRE_GLOBAL_KEY=1 in caller.
cf_global() {
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
      -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" \
      -H "Content-Type: application/json" \
      --data "$body"
  else
    curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
      -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
      -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}"
  fi
}

# cf_assert_success <response-json> <description>
cf_assert_success() {
  local resp="$1" desc="$2"
  local ok
  ok=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success'))")
  if [ "$ok" != "True" ]; then
    echo "ERROR: $desc failed:" >&2
    echo "$resp" | python3 -m json.tool >&2
    exit 1
  fi
}

# Resolve the user's Cloudflare account ID (cached for session).
# Always uses the global key — account tokens can read accounts but the
# fallback wrapper masks intermittent issues; for account ID we want
# determinism.
cf_account_id() {
  if [ -z "${_CF_ACCT_ID:-}" ]; then
    if [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
      _CF_ACCT_ID=$(curl -sS "https://api.cloudflare.com/client/v4/accounts?per_page=1" \
        -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" | python3 -c "
import json, sys
r = json.load(sys.stdin).get('result') or []
print(r[0]['id'] if r else '')")
    else
      _CF_ACCT_ID=$(cf_api GET "/accounts?per_page=1" | python3 -c "
import json, sys
r = json.load(sys.stdin).get('result') or []
print(r[0]['id'] if r else '')")
    fi
    [ -z "$_CF_ACCT_ID" ] && { echo "ERROR: could not resolve Cloudflare account ID" >&2; exit 1; }
    export _CF_ACCT_ID
  fi
  echo "$_CF_ACCT_ID"
}

# Find zone ID by name; empty string if not found.
cf_zone_id() {
  local domain="$1"
  cf_api GET "/zones?name=${domain}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
r = d.get('result') or []
print(r[0]['id'] if r else '')
"
}

# --- Namecheap API wrappers ---------------------------------------------

NC_USER="${NAMECHEAP_API_USER:-your-username}"

nc_my_ip() {
  curl -s https://api.ipify.org
}

# nc_get_hosts <sld> <tld>  → prints raw XML
nc_get_hosts() {
  local sld="$1" tld="$2"
  local ip
  ip=$(nc_my_ip)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${NC_USER}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${NC_USER}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.getHosts" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}"
}

# nc_get_nameservers <sld> <tld>  → prints current NS list, one per line
nc_get_nameservers() {
  local sld="$1" tld="$2"
  local ip
  ip=$(nc_my_ip)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${NC_USER}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${NC_USER}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.getList" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}" | grep -oE '<Nameserver>[^<]+</Nameserver>' | sed 's/<[^>]*>//g'
}

# nc_set_nameservers <sld> <tld> <ns1> <ns2> [ns3 ...]
nc_set_nameservers() {
  local sld="$1" tld="$2"
  shift 2
  local ns_csv
  ns_csv=$(IFS=,; echo "$*")
  local ip
  ip=$(nc_my_ip)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${NC_USER}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${NC_USER}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.setCustom" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}" \
    --data-urlencode "Nameservers=${ns_csv}"
}

# Reset NS back to Namecheap default (BasicDNS).
nc_reset_nameservers() {
  local sld="$1" tld="$2"
  local ip
  ip=$(nc_my_ip)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${NC_USER}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${NC_USER}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.setDefault" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}"
}

# Split a domain into SLD/TLD assuming single-label TLD
# (good enough for .com/.io/.ai/.app/.dev/.net/.org and most others).
# Two-label TLDs like .co.uk would need a public-suffix list; not handled.
domain_split() {
  local d="$1"
  local sld="${d%.*}"
  local tld="${d##*.}"
  echo "$sld $tld"
}

# Parse Namecheap getHosts XML → JSON list (uses python).
nc_hosts_to_json() {
  python3 -c "
import sys, re, json
xml = sys.stdin.read()
hosts = []
for m in re.finditer(r'<host\s+([^/]+)/>', xml):
    attrs = dict(re.findall(r'(\w+)=\"([^\"]*)\"', m.group(1)))
    hosts.append({
        'name':    attrs.get('Name', ''),
        'type':    attrs.get('Type', ''),
        'address': attrs.get('Address', ''),
        'mxpref':  attrs.get('MXPref', '10'),
        'ttl':     attrs.get('TTL', '300'),
    })
# also extract EmailType from the wrapper
em = re.search(r'EmailType=\"([^\"]*)\"', xml)
print(json.dumps({'email_type': em.group(1) if em else '', 'hosts': hosts}, indent=2))
"
}

# Convert a Namecheap host record → Cloudflare DNS record body.
# Stdin: one JSON record, stdout: one JSON record (Cloudflare body).
nc_to_cf_record() {
  local domain="$1"
  python3 -c "
import sys, json
domain = '$domain'
r = json.load(sys.stdin)
name = r['name']
fqdn = domain if name == '@' else f\"{name}.{domain}\"
out = {
    'type':    r['type'],
    'name':    fqdn,
    'content': r['address'].rstrip('.'),  # CF normalizes trailing dots
    'ttl':     int(r.get('ttl', 300)),
    'proxied': False,
    'comment': 'Imported from Namecheap by cloudflare-dns skill',
}
if r['type'] == 'MX':
    out['priority'] = int(r.get('mxpref', 10))
print(json.dumps(out))
"
}

# DoH-against-specific-NS query helper. Cloudflare's NS don't support DoH
# (only their public 1.1.1.1 resolver does), so for "query CF's NS directly"
# we send a UDP DNS packet via Python — see scripts/dns-direct-query.py.
dns_direct_query() {
  local ns_ip="$1" name="$2" type="${3:-A}"
  python3 "$(dirname "${BASH_SOURCE[0]}")/dns-direct-query.py" "$ns_ip" "$name" "$type"
}

# --- Cloudflare zone settings helpers -----------------------------------

# Set a single zone setting. Most settings live under /zones/{id}/settings/{name}
# and accept {"value": ...}.
cf_set_setting() {
  local zone_id="$1" name="$2" value="$3"
  cf_api PATCH "/zones/${zone_id}/settings/${name}" "{\"value\":${value}}"
}

# Update or create a DNS record.
#
# Match key:
#   - For most types: same {type, name} → PUT; else POST.
#   - For CAA: same {type, name, tag, value} → PUT; else POST.
#     A single name can hold multiple CAA records (issue letsencrypt.org +
#     issue pki.goog + issuewild ; + iodef mailto:…). Earlier versions of
#     this function matched on (type, name) only and blew them away on
#     each upsert — only the LAST CAA survived. Fixed here.
#   - For MX: same {type, name, priority, content} → PUT; else POST.
#     (apex commonly has 5 eforward MXes.)
#   - For TXT: same {type, name, content} → PUT; else POST.
#     (apex can hold SPF + DKIM + verification + …)
cf_upsert_record() {
  local zone_id="$1" body="$2"
  local rtype rname rcontent
  rtype=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin)['type'])")
  rname=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")

  local existing_id
  if [ "$rtype" = "CAA" ]; then
    # Match on (tag, value) inside the data object.
    local rtag rvalue
    rtag=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['tag'])")
    rvalue=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['value'])")
    existing_id=$(cf_api GET "/zones/${zone_id}/dns_records?type=CAA&name=${rname}&per_page=100" \
      | RTAG="$rtag" RVALUE="$rvalue" python3 -c "
import json, os, sys
rtag = os.environ['RTAG']; rvalue = os.environ['RVALUE']
recs = json.load(sys.stdin).get('result') or []
for r in recs:
    d = r.get('data') or {}
    if d.get('tag') == rtag and (d.get('value') or '').strip('\"') == rvalue.strip('\"'):
        print(r['id']); break")
  elif [ "$rtype" = "MX" ] || [ "$rtype" = "TXT" ]; then
    rcontent=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin)['content'])")
    existing_id=$(cf_api GET "/zones/${zone_id}/dns_records?type=${rtype}&name=${rname}&per_page=100" \
      | RC="$rcontent" python3 -c "
import json, os, sys
rc = os.environ['RC']
recs = json.load(sys.stdin).get('result') or []
for r in recs:
    if r.get('content') == rc:
        print(r['id']); break")
  else
    existing_id=$(cf_api GET "/zones/${zone_id}/dns_records?type=${rtype}&name=${rname}" \
      | python3 -c "import json,sys; r=json.load(sys.stdin).get('result') or []; print(r[0]['id'] if r else '')")
  fi

  if [ -n "$existing_id" ]; then
    cf_api PUT "/zones/${zone_id}/dns_records/${existing_id}" "$body"
  else
    cf_api POST "/zones/${zone_id}/dns_records" "$body"
  fi
}

# Toggle proxy (orange cloud) on a record by FQDN.
cf_set_proxy() {
  local zone_id="$1" fqdn="$2" proxied="$3"  # proxied = "true" or "false"
  local rec
  rec=$(cf_api GET "/zones/${zone_id}/dns_records?name=${fqdn}" \
    | python3 -c "
import json, sys
recs = json.load(sys.stdin).get('result') or []
# only flip A/AAAA/CNAME; never proxy MX/TXT/CAA
proxiable = [r for r in recs if r['type'] in ('A','AAAA','CNAME')]
print(json.dumps(proxiable))
")
  echo "$rec" | python3 -c "
import json, sys
for r in json.loads(sys.stdin.read()):
    print(r['id'])
" | while read -r record_id; do
    [ -z "$record_id" ] && continue
    cf_api PATCH "/zones/${zone_id}/dns_records/${record_id}" "{\"proxied\":${proxied}}" >/dev/null
  done
}
