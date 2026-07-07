#!/bin/bash
# Apply production hardening to a Cloudflare zone.
# Usage: ./harden.sh <domain> [--enable-proxy=true|false] [--rate-limit-path=/api/*] [--rate-limit-rpm=300] [--no-dnssec] [--dry-run]
#
# Tier 1 (no proxy needed):
#   - SSL: Full (strict)
#   - Always Use HTTPS = ON
#   - Min TLS = 1.2 + TLS 1.3 ON
#   - HSTS (1y, includeSubDomains, preload)
#   - Auto HTTPS rewrites
#   - Opportunistic encryption + 0-RTT + HTTP/3 + IPv6
#   - Browser integrity check
#   - Email obfuscation
#
# Tier 2 (proxy on):
#   - Flip @, www, api, docs to proxied (skip _acme-challenge.*)
#   - WAF Managed Ruleset = ON (free tier)
#   - Bot Fight Mode = ON
#   - Security Level = medium
#   - 1 rate-limit rule on chosen path
#
# Tier 3 (DNS-level):
#   - CAA records (letsencrypt + cloudflare allowed)
#   - DMARC TXT (p=none + rua reporting)
#   - DNSSEC enable + print DS record for registrar
#
# Idempotent — re-runnable safely. --dry-run prints planned mutations, writes nothing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain> [--enable-proxy=true|false] [...] [--dry-run]"; exit 1; }
shift || true

# Defaults
ENABLE_PROXY="true"
RL_PATH="/api/*"
RL_RPM="300"
DO_DNSSEC="true"
DRY_RUN="false"
PROXY_RECORDS=("@" "www" "api" "docs")

# Stable machine marker used to identify rate-limit rules this skill installed.
SKILL_MARKER="skill=cloudflare-dns"

while [ $# -gt 0 ]; do
  case "$1" in
    --enable-proxy=*)    ENABLE_PROXY="${1#*=}" ;;
    --rate-limit-path=*) RL_PATH="${1#*=}" ;;
    --rate-limit-rpm=*)  RL_RPM="${1#*=}" ;;
    --no-dnssec)         DO_DNSSEC="false" ;;
    --proxy-records=*)   IFS=',' read -ra PROXY_RECORDS <<< "${1#*=}" ;;
    --dry-run)           DRY_RUN="true" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

require_env CLOUDFLARE_API_KEY
DIR="$(state_dir "$DOMAIN")"
REPORT="${DIR}/hardening-report.md"

ZONE_ID="$(cf_zone_id "$DOMAIN")"
[ -z "$ZONE_ID" ] && { echo "ERROR: zone $DOMAIN not in Cloudflare. Run migrate.sh first." >&2; exit 1; }

echo "==============================================================="
echo "  Hardening: $DOMAIN  (zone ${ZONE_ID:0:8}***)"
[ "$DRY_RUN" = "true" ] && echo "  [DRY-RUN] no writes will be made"
echo "==============================================================="

ZONE_STATUS=$(cf_api GET "/zones/${ZONE_ID}" | python3 -c "
import json,sys; print(json.load(sys.stdin)['result']['status'])")
echo "  zone status: $ZONE_STATUS"
if [ "$ZONE_STATUS" != "active" ]; then
  echo "  [!] zone is '$ZONE_STATUS' — some features may need active status to apply."
  echo "     Settings will still be SAVED and take effect once zone activates."
fi
echo ""

if [ "$DRY_RUN" = "true" ]; then
  cat <<PLAN
[DRY-RUN] Would apply:

Tier 1 — SSL/TLS zone settings:
  ssl=strict, always_use_https=on, automatic_https_rewrites=on,
  min_tls_version=1.2, tls_1_3=on, opportunistic_encryption=on, 0rtt=on,
  http3=on, websockets=on, ipv6=on, email_obfuscation=on, browser_check=on,
  server_side_exclude=on
  HSTS: max-age=31536000, includeSubDomains, preload, nosniff

Tier 3 — DNS-level (adds/updates records):
  CAA @ issue "letsencrypt.org"
  CAA @ issue "pki.goog"
$( [ "$ENABLE_PROXY" = "true" ] && echo "  CAA @ issue \"digicert.com\"" )
  CAA @ issuewild ";"
  CAA @ iodef "mailto:postmaster@${DOMAIN}"
  TXT _dmarc.${DOMAIN}  "v=DMARC1; p=none; rua=mailto:postmaster@${DOMAIN}; ..."
$( [ "$DO_DNSSEC" = "true" ] && echo "  DNSSEC: enable (prints DS for registrar)" )

$( [ "$ENABLE_PROXY" = "true" ] && cat <<EOP
Tier 2 — Proxy + WAF (records to flip proxied=true):
$(for sub in "${PROXY_RECORDS[@]}"; do
    fqdn="$DOMAIN"; [ "$sub" != "@" ] && fqdn="${sub}.${DOMAIN}"
    echo "  proxied=true for ${fqdn}"
  done)
  Bot Fight Mode + JS Detection: ON
  Security Level: medium, Challenge TTL: 30min, Privacy Pass: on
  Rate limit: $(( RL_RPM / 6 )) req/10s/IP on ${RL_PATH}  (marker: ${SKILL_MARKER})
EOP
)

No writes made. Re-run without --dry-run to apply.
PLAN
  exit 0
fi

# Initialize report
cat > "$REPORT" <<EOF
# Cloudflare Hardening Report — $DOMAIN

**Date:** $(date -u +"%Y-%m-%d %H:%M UTC")
**Zone ID:** ${ZONE_ID:0:8}*** (full saved in cloudflare-zone.json)
**Zone status:** $ZONE_STATUS
**Proxy enabled:** $ENABLE_PROXY (records: ${PROXY_RECORDS[*]})
**DNSSEC enabled:** $DO_DNSSEC

EOF

# ---------------------------------------------------------------------------
apply_setting() {
  local label="$1" name="$2" value="$3"
  local resp
  resp=$(cf_set_setting "$ZONE_ID" "$name" "$value" 2>/dev/null || echo '{"success":false}')
  local ok
  ok=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success'))" 2>/dev/null)
  if [ "$ok" = "True" ]; then
    echo "  (OK) $label"
    echo "- (OK) \`$name\` = $value" >> "$REPORT"
  else
    local msg
    msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')" 2>/dev/null)
    echo "  FAIL $label — $msg"
    echo "- FAIL \`$name\` = $value (failed: $msg)" >> "$REPORT"
  fi
}

# ===========================================================================
# TIER 1 — SSL/TLS hardening (no proxy needed)
# ===========================================================================
echo "-- Tier 1: SSL/TLS hardening"
echo "" >> "$REPORT"
echo "## Tier 1 — SSL/TLS" >> "$REPORT"
echo "" >> "$REPORT"

apply_setting "SSL mode = Full (strict)"            "ssl"                   '"strict"'
apply_setting "Always Use HTTPS = ON"               "always_use_https"      '"on"'
apply_setting "Automatic HTTPS Rewrites = ON"       "automatic_https_rewrites" '"on"'
apply_setting "Min TLS Version = 1.2"               "min_tls_version"       '"1.2"'
apply_setting "TLS 1.3 = ON"                        "tls_1_3"               '"on"'
apply_setting "Opportunistic Encryption = ON"       "opportunistic_encryption" '"on"'
apply_setting "0-RTT = ON"                          "0rtt"                  '"on"'
apply_setting "HTTP/3 (QUIC) = ON"                  "http3"                 '"on"'
apply_setting "WebSockets = ON"                     "websockets"            '"on"'
apply_setting "IPv6 Compatibility = ON"             "ipv6"                  '"on"'
apply_setting "Email Address Obfuscation = ON"      "email_obfuscation"     '"on"'
apply_setting "Browser Integrity Check = ON"        "browser_check"         '"on"'
apply_setting "Server-Side Excludes = ON"           "server_side_exclude"   '"on"'

echo "  applying HSTS (max-age=31536000, includeSubDomains, preload)..."
HSTS_RESP=$(cf_api PATCH "/zones/${ZONE_ID}/settings/security_header" '{
  "value":{"strict_transport_security":{
    "enabled":true,"max_age":31536000,
    "include_subdomains":true,"preload":true,"nosniff":true
  }}
}')
if echo "$HSTS_RESP" | grep -q '"success":true'; then
  echo "  (OK) HSTS configured"
  echo "- (OK) HSTS: max-age=31536000, includeSubDomains, preload, nosniff" >> "$REPORT"
else
  msg=$(echo "$HSTS_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
  echo "  FAIL HSTS — $msg"
  echo "- FAIL HSTS — $msg" >> "$REPORT"
fi
echo ""

# ===========================================================================
# TIER 3 — DNS-level hardening (do BEFORE proxy flip so CAA covers cert reissue)
# ===========================================================================
echo "-- Tier 3: DNS-level hardening (CAA, DMARC, DNSSEC)"
echo "" >> "$REPORT"
echo "## Tier 3 — DNS-level" >> "$REPORT"
echo "" >> "$REPORT"

add_caa() {
  local tag="$1" value="$2"
  local body
  body=$(TAG="$tag" VAL="$value" DOM="$DOMAIN" python3 -c "
import json, os
print(json.dumps({
  'type':'CAA','name':os.environ['DOM'],'ttl':300,'proxied':False,
  'data':{'flags':0,'tag':os.environ['TAG'],'value':os.environ['VAL']},
  'comment':'Cert authority restriction (skill=cloudflare-dns)'
}))")
  local resp
  resp=$(cf_upsert_record "$ZONE_ID" "$body" 2>/dev/null)
  if echo "$resp" | grep -q '"success":true'; then
    echo "  (OK) CAA $tag \"$value\""
    echo "- (OK) CAA $tag \"$value\"" >> "$REPORT"
  else
    msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
    echo "  FAIL CAA $tag \"$value\" — $msg"
    echo "- FAIL CAA $tag \"$value\" — $msg" >> "$REPORT"
  fi
}
add_caa issue "letsencrypt.org"
add_caa issue "pki.goog"
[ "$ENABLE_PROXY" = "true" ] && add_caa issue "digicert.com"
add_caa issuewild ";"
add_caa iodef "mailto:postmaster@${DOMAIN}"

DMARC_BODY=$(DOM="$DOMAIN" python3 -c "
import json, os
d = os.environ['DOM']
print(json.dumps({
  'type':'TXT','name':f'_dmarc.{d}','ttl':300,'proxied':False,
  'content':f'\"v=DMARC1; p=none; rua=mailto:postmaster@{d}; ruf=mailto:postmaster@{d}; sp=none; adkim=r; aspf=r; pct=100\"',
  'comment':'DMARC monitor mode (skill=cloudflare-dns)'
}))")
DMARC_RESP=$(cf_upsert_record "$ZONE_ID" "$DMARC_BODY" 2>/dev/null)
if echo "$DMARC_RESP" | grep -q '"success":true'; then
  echo "  (OK) DMARC: p=none (monitor mode)"
  echo "- (OK) DMARC TXT at \`_dmarc.$DOMAIN\`: \`p=none\` monitor mode" >> "$REPORT"
else
  echo "  FAIL DMARC"
fi

if [ "$DO_DNSSEC" = "true" ]; then
  echo "  enabling DNSSEC..."
  DNSSEC_RESP=$(cf_api PATCH "/zones/${ZONE_ID}/dnssec" '{"status":"active"}')
  if echo "$DNSSEC_RESP" | grep -q '"success":true'; then
    # NB: previously this printed the algorithm number twice; look up its name.
    DS_KEY=$(echo "$DNSSEC_RESP" | python3 -c "
import json, sys
ALG = {
    1:'RSAMD5', 5:'RSASHA1', 7:'RSASHA1-NSEC3-SHA1', 8:'RSASHA256',
    10:'RSASHA512', 13:'ECDSAP256SHA256', 14:'ECDSAP384SHA384',
    15:'ED25519', 16:'ED448',
}
DTYPE = {1:'SHA-1', 2:'SHA-256', 4:'SHA-384'}
r = json.load(sys.stdin)['result']
alg = r.get('algorithm')
dt  = r.get('digest_type')
try: alg_n = int(alg)
except Exception: alg_n = 0
try: dt_n = int(dt)
except Exception: dt_n = 0
print(f\"  Key Tag:     {r.get('key_tag')}\")
print(f\"  Algorithm:   {alg_n} ({ALG.get(alg_n, 'unknown')})\")
print(f\"  Digest Type: {dt_n} ({DTYPE.get(dt_n, 'unknown')})\")
print(f\"  Digest:      {r.get('digest')}\")
print(f\"  DS Record:   {r.get('ds')}\")
print(f\"  Public Key:  {r.get('public_key')}\")
")
    echo "  (OK) DNSSEC enabled at Cloudflare"
    echo "$DS_KEY" | sed 's/^/      /'
    cat >> "$REPORT" <<EOF
- (OK) DNSSEC enabled at Cloudflare

\`\`\`
$DS_KEY
\`\`\`

[!] **Manual step required at registrar:** Submit the **DS Record** above to Namecheap so the parent zone signs Cloudflare's DNSKEY. Without this, DNSSEC is half-deployed.

For Namecheap: Domain List -> $DOMAIN -> Advanced DNS -> DNSSEC -> Add DS Record.
Namecheap's DNSSEC API is restricted; use \`scripts/dnssec-instructions.sh $DOMAIN\` for the exact copy-paste.
EOF

    echo "$DNSSEC_RESP" | python3 -c "
import json, sys, os
r = json.load(sys.stdin)['result']
os.makedirs('${DIR}', exist_ok=True)
with open('${DIR}/dnssec.json','w') as f:
    json.dump(r, f, indent=2)"
  else
    echo "  FAIL DNSSEC enable:"
    echo "$DNSSEC_RESP" | python3 -m json.tool | head -10
  fi
fi
echo ""

# ===========================================================================
# TIER 2 — Proxy + WAF + Bot + Rate Limit
# ===========================================================================
if [ "$ENABLE_PROXY" = "true" ]; then
  echo "-- Tier 2: Flipping proxy ON for ${PROXY_RECORDS[*]}"
  echo "" >> "$REPORT"
  echo "## Tier 2 — WAF + Proxy" >> "$REPORT"
  echo "" >> "$REPORT"

  for sub in "${PROXY_RECORDS[@]}"; do
    fqdn="$DOMAIN"
    [ "$sub" != "@" ] && fqdn="${sub}.${DOMAIN}"
    cf_set_proxy "$ZONE_ID" "$fqdn" "true"
    echo "  (OK) proxied: $fqdn"
    echo "- (OK) Proxy ON: \`$fqdn\`" >> "$REPORT"
  done
  echo ""

  echo "-- Verifying WAF Managed Free Ruleset is deployed"
  WAF_RS=$(cf_api GET "/zones/${ZONE_ID}/rulesets" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for rs in d.get('result', []):
    if rs.get('phase') == 'http_request_firewall_managed':
        print(json.dumps({'id': rs.get('id'), 'name': rs.get('name'), 'version': rs.get('version')}))
        break")
  if [ -n "$WAF_RS" ]; then
    WAF_NAME=$(echo "$WAF_RS" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    echo "  (OK) ${WAF_NAME} (auto-deployed for free zones)"
    echo "- (OK) WAF: ${WAF_NAME}" >> "$REPORT"
  else
    echo "  [!] No managed firewall ruleset found — may activate after zone goes active"
    echo "- [!] WAF Managed Ruleset not yet active (zone status pending?)" >> "$REPORT"
  fi

  echo "-- Enabling Bot Fight Mode + JS Detection"
  BOT_RESP=$(cf_api PUT "/zones/${ZONE_ID}/bot_management" '{"fight_mode":true,"enable_js":true}')
  BOT_OK=$(echo "$BOT_RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    r = d.get('result') or {}
    print('1' if d.get('success') and r.get('fight_mode') and r.get('enable_js') else '0')
except Exception:
    print('0')
")
  if [ "$BOT_OK" = "1" ]; then
    echo "  (OK) Bot Fight Mode = ON, JS Detection = ON"
    echo "- (OK) Bot Fight Mode + JS Detection = ON" >> "$REPORT"
  else
    CUR_BOT=$(cf_api GET "/zones/${ZONE_ID}/bot_management" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin).get('result') or {}
    print('1' if r.get('fight_mode') and r.get('enable_js') else '0')
except Exception:
    print('0')
")
    if [ "$CUR_BOT" = "1" ]; then
      echo "  (OK) Bot Fight Mode + JS Detection (already ON)"
      echo "- (OK) Bot Fight Mode + JS Detection (already ON)" >> "$REPORT"
    else
      msg=$(echo "$BOT_RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    errs = d.get('errors') or []
    print(errs[0].get('message') if errs else '(no error message)')
except Exception:
    print('(parse error)')
" 2>/dev/null)
      echo "  [!] Bot Fight Mode — $msg"
      echo "- [!] Bot Fight Mode — $msg" >> "$REPORT"
    fi
  fi

  apply_setting "Security Level = medium"   "security_level"     '"medium"'
  apply_setting "Challenge TTL = 30min"     "challenge_ttl"      "1800"
  apply_setting "Privacy Pass = ON"         "privacy_pass"       '"on"'

  # Rate limit — free tier: period=10, mitigation_timeout=10, one rule/zone.
  echo "-- Adding rate-limit rule: ${RL_PATH} -> ${RL_RPM}/min/IP"

  RL_PATH_PREFIX="${RL_PATH%\*}"
  if [ "$RL_PATH" != "$RL_PATH_PREFIX" ]; then
    RL_EXPR='(starts_with(http.request.uri.path, "'${RL_PATH_PREFIX}'"))'
  else
    RL_EXPR='(http.request.uri.path eq "'${RL_PATH}'")'
  fi
  RL_REQS_10S=$(( RL_RPM / 6 ))
  [ "$RL_REQS_10S" -lt 1 ] && RL_REQS_10S=1

  # Existing entrypoint OR any zone-kind ruleset in this phase
  RL_EXISTING=$(cf_api GET "/zones/${ZONE_ID}/rulesets" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for rs in d.get('result', []):
    if rs.get('phase') == 'http_ratelimit':
        print(rs.get('id', ''))
        break")
  if [ -n "$RL_EXISTING" ]; then
    echo "  (OK) Rate-limit ruleset already deployed (id ${RL_EXISTING:0:8}***)"
    cf_api GET "/zones/${ZONE_ID}/rulesets/${RL_EXISTING}" | python3 -c "
import json, sys
r = json.load(sys.stdin).get('result') or {}
for rule in r.get('rules', []):
    rl = rule.get('ratelimit', {})
    print(f\"     {rule.get('description','?')} ({rl.get('requests_per_period','?')} req/{rl.get('period','?')}s)\")"
    echo "- (OK) Rate limit (existing): preserved" >> "$REPORT"
    RL_PHASE='__SKIP__'
  else
    RL_PHASE=$(cf_api GET "/zones/${ZONE_ID}/rulesets/phases/http_ratelimit/entrypoint")
  fi

  if [ "$RL_PHASE" != "__SKIP__" ] && echo "$RL_PHASE" | grep -q '"success":true'; then
    RL_RS_ID=$(echo "$RL_PHASE" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
    HAS_SKILL_RULE=$(MARKER="$SKILL_MARKER" echo "$RL_PHASE" | MARKER="$SKILL_MARKER" python3 -c "
import json, os, sys
marker = os.environ['MARKER']
rules = (json.load(sys.stdin).get('result') or {}).get('rules') or []
print('1' if any(marker in (r.get('description','') or '') for r in rules) else '0')
")
    if [ "$HAS_SKILL_RULE" = "1" ]; then
      echo "  (OK) skill-managed rate-limit already present — skipping (idempotent)"
      echo "- (OK) Rate limit (already configured): ${RL_REQS_10S} req/10s on \`${RL_PATH}\`" >> "$REPORT"
    else
      RL_RULE=$(MARKER="$SKILL_MARKER" REQS10="$RL_REQS_10S" RLPATH="$RL_PATH" RL_EXPR_ENV="$RL_EXPR" python3 -c "
import json, os
print(json.dumps({
  'description': f\"{os.environ['MARKER']}: {os.environ['REQS10']} req/10s per IP on {os.environ['RLPATH']}\",
  'expression': os.environ['RL_EXPR_ENV'],
  'action': 'block',
  'ratelimit': {
    'characteristics': ['cf.colo.id', 'ip.src'],
    'period': 10,
    'requests_per_period': int(os.environ['REQS10']),
    'mitigation_timeout': 10
  }
}))")
      RL_RESP=$(cf_api POST "/zones/${ZONE_ID}/rulesets/${RL_RS_ID}/rules" "$RL_RULE")
      if echo "$RL_RESP" | grep -q '"success":true'; then
        echo "  (OK) rate limit added: ${RL_REQS_10S} req/10s/IP on ${RL_PATH}"
        echo "- (OK) Rate limit: ${RL_REQS_10S} req/10s/IP on \`${RL_PATH}\` (~${RL_RPM} rpm)" >> "$REPORT"
      else
        msg=$(echo "$RL_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
        echo "  [!] rate limit — $msg"
        echo "- [!] Rate limit — $msg" >> "$REPORT"
      fi
    fi
  elif [ "$RL_PHASE" != "__SKIP__" ]; then
    RL_BODY=$(MARKER="$SKILL_MARKER" REQS10="$RL_REQS_10S" RLPATH="$RL_PATH" RL_EXPR_ENV="$RL_EXPR" python3 -c "
import json, os
print(json.dumps({
  'name': f\"{os.environ['MARKER']} zone rate limiting\",
  'description': f\"Rate limit rules deployed by the cloudflare-dns skill ({os.environ['MARKER']})\",
  'kind': 'zone',
  'phase': 'http_ratelimit',
  'rules': [{
    'description': f\"{os.environ['MARKER']}: {os.environ['REQS10']} req/10s per IP on {os.environ['RLPATH']}\",
    'expression': os.environ['RL_EXPR_ENV'],
    'action': 'block',
    'ratelimit': {
      'characteristics': ['cf.colo.id', 'ip.src'],
      'period': 10,
      'requests_per_period': int(os.environ['REQS10']),
      'mitigation_timeout': 10
    }
  }]
}))")
    RL_RESP=$(cf_api POST "/zones/${ZONE_ID}/rulesets" "$RL_BODY")
    if echo "$RL_RESP" | grep -q '"success":true'; then
      echo "  (OK) rate limit applied: ${RL_REQS_10S} req/10s/IP on ${RL_PATH}"
      echo "- (OK) Rate limit: ${RL_REQS_10S} req/10s/IP on \`${RL_PATH}\` (~${RL_RPM} rpm)" >> "$REPORT"
    else
      msg=$(echo "$RL_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
      echo "  [!] rate limit — $msg"
      echo "- [!] Rate limit — $msg" >> "$REPORT"
    fi
  fi
  echo ""
fi

# ===========================================================================
# Live verification — only hit subdomains we actually have records for.
# ===========================================================================
echo "-- Live HTTP smoke test"
echo "" >> "$REPORT"
echo "## Post-hardening live test" >> "$REPORT"
echo "" >> "$REPORT"
echo '```' >> "$REPORT"

# Fetch the record set once and probe only the hosts that exist.
SMOKE_HOSTS=$(cf_api GET "/zones/${ZONE_ID}/dns_records?per_page=100" | DOM="$DOMAIN" python3 -c "
import json, sys, os
domain = os.environ['DOM']
recs = json.load(sys.stdin).get('result') or []
hosts = set()
for r in recs:
    if r.get('type') in ('A','AAAA','CNAME'):
        n = r['name']
        if n == domain:
            hosts.add(domain)
        elif n.endswith('.' + domain):
            hosts.add(n)
# always keep apex as a probe
hosts.add(domain)
print('\n'.join(sorted(hosts)))")

while IFS= read -r host; do
  [ -z "$host" ] && continue
  status=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | head -1 | tr -d '\r')
  hsts=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | grep -i "strict-transport" | head -1 | tr -d '\r')
  server=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | grep -i "^server:" | head -1 | tr -d '\r')
  printf "  %-30s %s\n  %s\n  %s\n\n" "$host" "${status:-FAIL}" "$server" "$hsts"
  printf "%-30s %s\n  %s\n  %s\n\n" "$host" "${status:-FAIL}" "$server" "$hsts" >> "$REPORT"
done <<< "$SMOKE_HOSTS"
echo '```' >> "$REPORT"

echo ""
echo "==============================================================="
echo "  Hardening complete"
echo "  Report saved: $REPORT"
echo "==============================================================="
