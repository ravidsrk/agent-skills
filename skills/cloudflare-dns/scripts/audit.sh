#!/bin/bash
# Read-only audit of a domain's DNS state.
# Usage: ./audit.sh <domain>
#
# Outputs:
#   - registrar nameservers
#   - all host records at the registrar (authoritative)
#   - whether Cloudflare zone exists
#   - if zone exists, all records there too
#   - delta between the two (aware of Namecheap eforward MX injection)
#
# Writes JSON to .dns-state/<domain>/audit-pre.json on first run
# (won't overwrite — that file is the migration baseline).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

require_env CLOUDFLARE_API_KEY NAMECHEAP_API_KEY NAMECHEAP_API_USER

read -r SLD TLD <<< "$(domain_split "$DOMAIN")"
DIR="$(state_dir "$DOMAIN")"

echo "==============================================================="
echo "  DNS Audit: $DOMAIN"
echo "==============================================================="
echo ""

# 1. Registrar nameservers
echo "-- Namecheap nameservers:"
NC_NS=$(nc_get_nameservers "$SLD" "$TLD")
if [ -z "$NC_NS" ]; then
  echo "    (none returned — the API call may have failed; check IP whitelist)"
else
  echo "$NC_NS" | sed 's/^/    /'
fi
echo ""

# 2. Registrar host records — write to disk so python reads by file (safer than string interp)
echo "-- Namecheap host records:"
NC_XML=$(nc_get_hosts "$SLD" "$TLD")
echo "$NC_XML" | nc_hosts_to_json > "${DIR}/.namecheap-raw.json"

DIR_ENV="$DIR" python3 - <<'PYEOF'
import json, os
data = json.load(open(os.path.join(os.environ['DIR_ENV'], '.namecheap-raw.json')))
if 'error' in data:
    print(f"    XML parse error: {data['error']}")
print(f"    EmailType: {data.get('email_type','')}  ({len(data['hosts'])} records)")
UNSUPPORTED = {'URL', 'URL301', 'FRAME'}
for h in data['hosts']:
    name = h['name'] if h['name'] != '@' else '(apex)'
    typ = (h['type'] or '').upper()
    marker = '  [!] unsupported for CF DNS' if typ in UNSUPPORTED else ''
    print(f"    {h['type']:<6} {name:<40} -> {h['address']}{marker}")
PYEOF
echo ""

# Save baseline if first run — but refuse to save an empty NS list.
if [ ! -f "${DIR}/audit-pre.json" ]; then
  if [ -z "$NC_NS" ]; then
    echo "    [WARN] refusing to save empty NS list as baseline — audit-pre.json NOT written"
    echo "           fix the Namecheap API call first (usually IP whitelist), then re-run audit"
  else
    NC_NS_ENV="$NC_NS" DIR_ENV="$DIR" DOMAIN_ENV="$DOMAIN" python3 - <<'PYEOF'
import json, os
ns_lines = [ns.strip() for ns in os.environ['NC_NS_ENV'].strip().split('\n') if ns.strip()]
if not ns_lines:
    raise SystemExit("refusing to save empty NS baseline")
nc = json.load(open(os.path.join(os.environ['DIR_ENV'], '.namecheap-raw.json')))
data = {
    'domain': os.environ['DOMAIN_ENV'],
    'nameservers': ns_lines,
    'records': nc,
}
with open(os.path.join(os.environ['DIR_ENV'], 'audit-pre.json'), 'w') as f:
    json.dump(data, f, indent=2)
print(f"    [saved baseline -> {os.environ['DIR_ENV']}/audit-pre.json]")
PYEOF
  fi
fi

# 3. Cloudflare zone state
echo "-- Cloudflare zone:"
ZONE_RESP=$(cf_api GET "/zones?name=${DOMAIN}")
cf_assert_success "$ZONE_RESP" "list zones"
ZONE_COUNT=$(echo "$ZONE_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['result_info']['count'])")

if [ "$ZONE_COUNT" = "0" ]; then
  echo "    [not yet in Cloudflare]"
  rm -f "${DIR}/.namecheap-raw.json"
  echo ""
  echo "  -> next step: ./migrate.sh $DOMAIN create"
  exit 0
fi

ZONE_ID=$(echo "$ZONE_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0]['id'])")
ZONE_DETAIL=$(echo "$ZONE_RESP" | python3 -c "
import json,sys
z = json.load(sys.stdin)['result'][0]
print(f'    status:      {z[\"status\"]}')
print(f'    plan:        {z[\"plan\"][\"name\"]}')
print(f'    nameservers: {\", \".join(z.get(\"name_servers\", []))}')
print(f'    created:     {z[\"created_on\"][:19]}')
")
echo "$ZONE_DETAIL"
echo "    zone_id:     ${ZONE_ID:0:8}***"
echo ""

# 4. Cloudflare records
echo "-- Cloudflare records:"
cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=100" > "${DIR}/.cf-records-raw.json"
cf_assert_success "$(cat "${DIR}/.cf-records-raw.json")" "list records"
DOMAIN_ENV="$DOMAIN" CF_RECS_FILE="${DIR}/.cf-records-raw.json" python3 - <<'PYEOF'
import json, os
d = json.load(open(os.environ['CF_RECS_FILE']))
recs = d.get('result', [])
suffix = os.environ['DOMAIN_ENV']
print(f'    ({len(recs)} records)')
for r in recs:
    n = r['name']
    n = '(apex)' if n == suffix else n.rsplit('.'+suffix,1)[0] if n.endswith('.'+suffix) else n
    proxy = '[proxied]' if r.get('proxied') else '[dns-only]'
    extra = f' priority={r["priority"]}' if r['type'] == 'MX' else ''
    print(f'    {r["type"]:<5} {n:<40} -> {r["content"]}{extra} {proxy}')
PYEOF
echo ""

# 5. Delta — aware of Namecheap eforward MXes and URL-redirect record types
echo "-- Delta (records at Namecheap NOT in Cloudflare):"
DOMAIN_ENV="$DOMAIN" NC_JSON_FILE="${DIR}/.namecheap-raw.json" CF_RECS_FILE="${DIR}/.cf-records-raw.json" python3 - <<'PYEOF'
import json, os
domain = os.environ['DOMAIN_ENV']
nc = json.load(open(os.environ['NC_JSON_FILE']))
cf = json.load(open(os.environ['CF_RECS_FILE']))['result']

SUPPORTED = {'A', 'AAAA', 'CNAME', 'MX', 'TXT', 'CAA', 'SRV', 'NS'}
EFORWARD_MX_HOSTS = {f'eforward{i}.registrar-servers.com' for i in (1, 2, 3, 4, 5)}

def fqdn(n):
    return domain if n in ('@', '') else f'{n}.{domain}'

def key(rtype, name, content):
    return (rtype.upper(), name.lower(), (content or '').rstrip('.').lower())

nc_keys = set()
nc_unsupported = []
for h in nc.get('hosts', []):
    typ = (h.get('type') or '').upper()
    if typ not in SUPPORTED:
        nc_unsupported.append(h)
        continue
    nc_keys.add(key(typ, fqdn(h['name']), h['address']))

cf_keys = {key(r['type'], r['name'], r['content']) for r in cf}

missing = nc_keys - cf_keys
extra   = cf_keys - nc_keys

if nc_unsupported:
    for h in nc_unsupported:
        print(f"    [!] Namecheap has unsupported-for-CF record: {h['type']:<6} {h['name']:<30} -> {h['address']}")
        print(f"        (map to a Cloudflare Redirect Rule instead of a DNS record)")
    print()

if not missing:
    print('    (OK) all Namecheap records present in Cloudflare')
else:
    for k in sorted(missing):
        print(f'    MISSING in CF: {k[0]:<5} {k[1]} -> {k[2]}')

if extra:
    print()
    print('-- In Cloudflare but NOT at Namecheap:')
    for k in sorted(extra):
        # ignore CF auto-generated SOA/NS for the apex
        if k[0] in ('SOA', 'NS') and k[1] == domain.lower():
            continue
        # label eforward MXes that Namecheap auto-injects (never in getHosts)
        note = ''
        if k[0] == 'MX' and any(k[2].startswith(h) or k[2] == h for h in EFORWARD_MX_HOSTS):
            note = '   [Namecheap-auto-injected forwarding MX — expected if EmailType=FWD was preserved]'
        print(f'    EXTRA in CF: {k[0]:<5} {k[1]} -> {k[2]}{note}')
PYEOF

# Clean up scratch files
rm -f "${DIR}/.namecheap-raw.json" "${DIR}/.cf-records-raw.json"

echo ""
echo "==============================================================="
