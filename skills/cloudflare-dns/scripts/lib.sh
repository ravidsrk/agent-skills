#!/bin/bash
# Shared helpers for cloudflare-dns scripts.
# Source this from the other scripts via: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# --- env validation ------------------------------------------------------

# require_env <var> [<var> ...]
#
# Each caller declares only the env vars it actually needs.
# Common groupings:
#   require_env CLOUDFLARE_API_KEY                                       # CF-only ops
#   require_env CLOUDFLARE_API_KEY NAMECHEAP_API_KEY NAMECHEAP_API_USER  # migrate/audit/rollback
#   require_env CLOUDFLARE_GLOBAL_API_KEY CLOUDFLARE_EMAIL               # zone-create only
require_env() {
  local missing=()
  local v
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      missing+=("$v")
    fi
  done
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
# Uses the ACCOUNT TOKEN (Bearer) by default.
#
# If CF_AUTO_FALLBACK=1 is set AND the account token gets an auth-related
# error (Cloudflare codes 10000, 9109, 6003), automatically retries with
# the Global API Key + email header pair. Off by default because it grants
# broader privilege than the caller asked for; opt in explicitly:
#   CF_AUTO_FALLBACK=1 scripts/harden.sh example.com
# When it fires, a one-line notice is printed to stderr so it's never silent.
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

  # Opt-in Global-Key fallback on auth errors.
  if [ "${CF_AUTO_FALLBACK:-0}" = "1" ] \
     && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] \
     && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
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
    if [ "$needs_fallback" = "1" ]; then
      echo "cf_api: account-token auth failed on ${method} ${path}; falling back to CLOUDFLARE_GLOBAL_API_KEY (CF_AUTO_FALLBACK=1)" >&2
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
  fi
  printf '%s' "$resp"
}

# cf_global <method> <path> [<body-json>]  — uses GLOBAL KEY (email + key)
# Use only for zone creation (POST /zones). Callers must have called:
#   require_env CLOUDFLARE_GLOBAL_API_KEY CLOUDFLARE_EMAIL
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
# Prefers the account token; falls back to global key only if the account
# token can't list accounts (some scoped tokens can't).
cf_account_id() {
  if [ -z "${_CF_ACCT_ID:-}" ]; then
    _CF_ACCT_ID=$(cf_api GET "/accounts?per_page=1" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin).get('result') or []
    print(r[0]['id'] if r else '')
except Exception:
    print('')")
    if [ -z "$_CF_ACCT_ID" ] && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
      _CF_ACCT_ID=$(curl -sS "https://api.cloudflare.com/client/v4/accounts?per_page=1" \
        -H "X-Auth-Key: ${CLOUDFLARE_GLOBAL_API_KEY}" \
        -H "X-Auth-Email: ${CLOUDFLARE_EMAIL}" | python3 -c "
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

# Callers must have already run: require_env NAMECHEAP_API_USER
# No placeholder default — an unset var must be an explicit error.
_nc_user() { echo "${NAMECHEAP_API_USER:-}"; }

nc_my_ip() {
  curl -s https://api.ipify.org
}

# nc_get_hosts <sld> <tld>  → prints raw XML
nc_get_hosts() {
  local sld="$1" tld="$2"
  local ip user
  ip=$(nc_my_ip)
  user=$(_nc_user)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${user}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${user}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.getHosts" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}"
}

# nc_get_nameservers <sld> <tld>  → prints current NS list, one per line
# Uses xml.etree so URL-redirect records or attribute changes don't break parsing.
nc_get_nameservers() {
  local sld="$1" tld="$2"
  local ip user
  ip=$(nc_my_ip)
  user=$(_nc_user)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${user}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${user}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.getList" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}" | python3 -c "
import sys, xml.etree.ElementTree as ET
raw = sys.stdin.read()
try:
    root = ET.fromstring(raw)
except ET.ParseError:
    sys.exit(0)
# Namespace strip so we can iterate by local tag name
for el in root.iter():
    if '}' in el.tag:
        el.tag = el.tag.split('}', 1)[1]
for ns in root.iter('Nameserver'):
    txt = (ns.text or '').strip()
    if txt:
        print(txt)
"
}

# nc_set_nameservers <sld> <tld> <ns1> <ns2> [ns3 ...]
nc_set_nameservers() {
  local sld="$1" tld="$2"
  shift 2
  if [ $# -eq 0 ]; then
    echo "ERROR: nc_set_nameservers called with no nameservers" >&2
    return 1
  fi
  local ns
  for ns in "$@"; do
    if [ -z "$ns" ]; then
      echo "ERROR: nc_set_nameservers received an empty nameserver arg" >&2
      return 1
    fi
  done
  local ns_csv
  ns_csv=$(IFS=,; echo "$*")
  local ip user
  ip=$(nc_my_ip)
  user=$(_nc_user)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${user}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${user}" \
    --data-urlencode "ClientIp=${ip}" \
    --data-urlencode "Command=namecheap.domains.dns.setCustom" \
    --data-urlencode "SLD=${sld}" \
    --data-urlencode "TLD=${tld}" \
    --data-urlencode "Nameservers=${ns_csv}"
}

# Reset NS back to Namecheap default (BasicDNS).
nc_reset_nameservers() {
  local sld="$1" tld="$2"
  local ip user
  ip=$(nc_my_ip)
  user=$(_nc_user)
  curl -sS -G "https://api.namecheap.com/xml.response" \
    --data-urlencode "ApiUser=${user}" \
    --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
    --data-urlencode "UserName=${user}" \
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

# Parse Namecheap getHosts XML → JSON list using xml.etree (not regex).
# Handles URL/URL301/FRAME records whose Address contains '/' — the old
# regex silently dropped those; the parser keeps them so we can warn
# clearly when they can't map to a Cloudflare DNS record.
nc_hosts_to_json() {
  python3 -c "
import sys, json, xml.etree.ElementTree as ET

raw = sys.stdin.read()
try:
    root = ET.fromstring(raw)
except ET.ParseError as e:
    print(json.dumps({'error': f'malformed XML: {e}', 'email_type': '', 'hosts': []}))
    sys.exit(0)

for el in root.iter():
    if '}' in el.tag:
        el.tag = el.tag.split('}', 1)[1]

email_type = ''
dhr = root.find('.//DomainDNSGetHostsResult')
if dhr is not None:
    email_type = dhr.attrib.get('EmailType', '')

hosts = []
for h in root.iter('host'):
    a = h.attrib
    hosts.append({
        'name':    a.get('Name', ''),
        'type':    a.get('Type', ''),
        'address': a.get('Address', ''),
        'mxpref':  a.get('MXPref', '10'),
        'ttl':     a.get('TTL', '300'),
    })

print(json.dumps({'email_type': email_type, 'hosts': hosts}, indent=2))
"
}

# Convert a Namecheap host record → Cloudflare DNS record body.
# Stdin: one JSON record.
# Stdout:
#   - one JSON Cloudflare-record body   (for supported types)
#   - the exact string 'SKIP:<reason>'  (for unsupported types like URL/URL301/FRAME)
# For URL redirects, use a Cloudflare Redirect Rule (dashboard: Rules →
# Redirect Rules), not a DNS record.
nc_to_cf_record() {
  local domain="$1"
  python3 -c "
import sys, json
domain = '$domain'
r = json.load(sys.stdin)

SUPPORTED = {'A', 'AAAA', 'CNAME', 'MX', 'TXT', 'CAA', 'SRV', 'NS'}
rtype = (r.get('type') or '').upper()

if rtype not in SUPPORTED:
    print(f'SKIP:{rtype or \"UNKNOWN\"} type not a Cloudflare DNS record — configure a Cloudflare Redirect Rule (Rules -> Redirect Rules) instead for URL forwarding')
    sys.exit(0)

name = r['name']
fqdn = domain if name == '@' else f\"{name}.{domain}\"
out = {
    'type':    rtype,
    'name':    fqdn,
    'content': r['address'].rstrip('.'),
    'ttl':     int(r.get('ttl', 300)),
    'proxied': False,
    'comment': 'Imported from Namecheap by cloudflare-dns skill',
}
if rtype == 'MX':
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
#   - For MX: same {type, name, content} → PUT; else POST.
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
