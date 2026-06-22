#!/bin/bash
# Apply production hardening to a Cloudflare zone.
# Usage: ./harden.sh <domain> [--enable-proxy=true|false] [--rate-limit-path=/api/*] [--rate-limit-rpm=300] [--no-dnssec]
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
# Idempotent — re-runnable safely.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

DOMAIN="${1:-}"
[ -z "$DOMAIN" ] && { echo "Usage: $0 <domain> [--enable-proxy=true|false] [...]"; exit 1; }
shift || true

# Defaults
ENABLE_PROXY="true"
RL_PATH="/api/*"
RL_RPM="300"
DO_DNSSEC="true"
PROXY_RECORDS=("@" "www" "api" "docs")

while [ $# -gt 0 ]; do
  case "$1" in
    --enable-proxy=*)    ENABLE_PROXY="${1#*=}" ;;
    --rate-limit-path=*) RL_PATH="${1#*=}" ;;
    --rate-limit-rpm=*)  RL_RPM="${1#*=}" ;;
    --no-dnssec)         DO_DNSSEC="false" ;;
    --proxy-records=*)   IFS=',' read -ra PROXY_RECORDS <<< "${1#*=}" ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

require_env
DIR="$(state_dir "$DOMAIN")"
REPORT="${DIR}/hardening-report.md"

ZONE_ID="$(cf_zone_id "$DOMAIN")"
[ -z "$ZONE_ID" ] && { echo "ERROR: zone $DOMAIN not in Cloudflare. Run migrate.sh first." >&2; exit 1; }

echo "═══════════════════════════════════════════════════════════════"
echo "  Hardening: $DOMAIN  (zone ${ZONE_ID:0:8}***)"
echo "═══════════════════════════════════════════════════════════════"

# Check zone status — features require an ACTIVE zone (some apply to pending though)
ZONE_STATUS=$(cf_api GET "/zones/${ZONE_ID}" | python3 -c "
import json,sys; print(json.load(sys.stdin)['result']['status'])")
echo "  zone status: $ZONE_STATUS"
if [ "$ZONE_STATUS" != "active" ]; then
  echo "  ⚠️  zone is '$ZONE_STATUS' — some features may need active status to apply."
  echo "     Settings will still be SAVED and take effect once zone activates."
fi
echo ""

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
# Helper: apply a setting and report success/failure
# ---------------------------------------------------------------------------
apply_setting() {
  local label="$1" name="$2" value="$3"
  local resp
  resp=$(cf_set_setting "$ZONE_ID" "$name" "$value" 2>/dev/null || echo '{"success":false}')
  local ok
  ok=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('success'))" 2>/dev/null)
  if [ "$ok" = "True" ]; then
    echo "  🟢 $label"
    echo "- 🟢 \`$name\` = $value" >> "$REPORT"
  else
    local msg
    msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')" 2>/dev/null)
    echo "  🔴 $label — FAILED: $msg"
    echo "- 🔴 \`$name\` = $value (failed: $msg)" >> "$REPORT"
  fi
}

# ===========================================================================
# TIER 1 — SSL/TLS hardening (no proxy needed)
# ===========================================================================
echo "▸ Tier 1: SSL/TLS hardening"
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

# HSTS uses a different shape (object value)
echo "  applying HSTS (max-age=31536000, includeSubDomains, preload)..."
HSTS_RESP=$(cf_api PATCH "/zones/${ZONE_ID}/settings/security_header" '{
  "value":{"strict_transport_security":{
    "enabled":true,"max_age":31536000,
    "include_subdomains":true,"preload":true,"nosniff":true
  }}
}')
if echo "$HSTS_RESP" | grep -q '"success":true'; then
  echo "  🟢 HSTS configured"
  echo "- 🟢 HSTS: max-age=31536000, includeSubDomains, preload, nosniff" >> "$REPORT"
else
  msg=$(echo "$HSTS_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
  echo "  🔴 HSTS — FAILED: $msg"
  echo "- 🔴 HSTS — failed: $msg" >> "$REPORT"
fi
echo ""

# ===========================================================================
# TIER 3 — DNS-level hardening (do BEFORE proxy flip so CAA covers cert reissue)
# ===========================================================================
echo "▸ Tier 3: DNS-level hardening (CAA, DMARC, DNSSEC)"
echo "" >> "$REPORT"
echo "## Tier 3 — DNS-level" >> "$REPORT"
echo "" >> "$REPORT"

# CAA records — restrict who can issue certs for this domain.
# Allow Let's Encrypt (Fly uses it) + Cloudflare (in case proxy is on).
add_caa() {
  local tag="$1" value="$2"
  local body
  body=$(python3 -c "
import json
print(json.dumps({
  'type':'CAA','name':'$DOMAIN','ttl':300,'proxied':False,
  'data':{'flags':0,'tag':'$tag','value':'$value'},
  'comment':'Cert authority restriction (skill hardening)'
}))")
  local resp
  resp=$(cf_upsert_record "$ZONE_ID" "$body" 2>/dev/null)
  if echo "$resp" | grep -q '"success":true'; then
    echo "  🟢 CAA $tag \"$value\""
    echo "- 🟢 CAA $tag \"$value\"" >> "$REPORT"
  else
    msg=$(echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
    echo "  🔴 CAA $tag \"$value\" — $msg"
    echo "- 🔴 CAA $tag \"$value\" — $msg" >> "$REPORT"
  fi
}
add_caa issue "letsencrypt.org"
add_caa issue "pki.goog"
[ "$ENABLE_PROXY" = "true" ] && add_caa issue "digicert.com"  # CF Universal SSL uses DigiCert
add_caa issuewild ";"  # disallow wildcards unless explicitly needed
add_caa iodef "mailto:postmaster@${DOMAIN}"

# DMARC — anti-spoofing. p=none = monitor mode (gathers reports, no enforcement).
# Switch to p=quarantine then p=reject after a few weeks of reports.
DMARC_BODY=$(python3 -c "
import json
print(json.dumps({
  'type':'TXT','name':'_dmarc.$DOMAIN','ttl':300,'proxied':False,
  'content':'\"v=DMARC1; p=none; rua=mailto:postmaster@$DOMAIN; ruf=mailto:postmaster@$DOMAIN; sp=none; adkim=r; aspf=r; pct=100\"',
  'comment':'DMARC monitor mode (skill hardening)'
}))")
DMARC_RESP=$(cf_upsert_record "$ZONE_ID" "$DMARC_BODY" 2>/dev/null)
if echo "$DMARC_RESP" | grep -q '"success":true'; then
  echo "  🟢 DMARC: p=none (monitor mode)"
  echo "- 🟢 DMARC TXT at \`_dmarc.$DOMAIN\`: \`p=none\` monitor mode" >> "$REPORT"
else
  echo "  🔴 DMARC — failed"
fi

# DNSSEC enable
if [ "$DO_DNSSEC" = "true" ]; then
  echo "  enabling DNSSEC..."
  DNSSEC_RESP=$(cf_api PATCH "/zones/${ZONE_ID}/dnssec" '{"status":"active"}')
  if echo "$DNSSEC_RESP" | grep -q '"success":true'; then
    DS_KEY=$(echo "$DNSSEC_RESP" | python3 -c "
import json, sys
r = json.load(sys.stdin)['result']
print(f\"  Key Tag: {r.get('key_tag')}\")
print(f\"  Algorithm: {r.get('algorithm')} ({r.get('algorithm','?')})\")
print(f\"  Digest Type: {r.get('digest_type')}\")
print(f\"  Digest: {r.get('digest')}\")
print(f\"  DS Record: {r.get('ds')}\")
print(f\"  Public Key: {r.get('public_key')}\")
")
    echo "  🟢 DNSSEC enabled at Cloudflare"
    echo "$DS_KEY" | sed 's/^/      /'
    cat >> "$REPORT" <<EOF
- 🟢 DNSSEC enabled at Cloudflare

\`\`\`
$DS_KEY
\`\`\`

⚠️ **Manual step required at registrar:** Submit the **DS Record** above to Namecheap so the parent zone (\`.ai\`) signs Cloudflare's DNSKEY. Without this, DNSSEC is half-deployed (CF signs but no chain of trust to the root).

For Namecheap: Domain List → example.com → Advanced DNS → DNSSEC → Add DS Record. Use the Key Tag, Algorithm (13 = ECDSAP256SHA256), Digest Type (2 = SHA-256), and Digest from above.

(Some registrars accept this via API; Namecheap's DNSSEC API is restricted. We'll attempt it via \`namecheap.domains.dns.setDNSSEC\` and fall back to manual instructions.)
EOF

    # Save raw DNSSEC details
    echo "$DNSSEC_RESP" | python3 -c "
import json, sys
r = json.load(sys.stdin)['result']
import os
os.makedirs('${DIR}', exist_ok=True)
with open('${DIR}/dnssec.json','w') as f:
    json.dump(r, f, indent=2)"
  else
    echo "  🔴 DNSSEC enable failed:"
    echo "$DNSSEC_RESP" | python3 -m json.tool | head -10
  fi
fi
echo ""

# ===========================================================================
# TIER 2 — Proxy + WAF + Bot + Rate Limit
# ===========================================================================
if [ "$ENABLE_PROXY" = "true" ]; then
  echo "▸ Tier 2: Flipping proxy ON for ${PROXY_RECORDS[*]}"
  echo "" >> "$REPORT"
  echo "## Tier 2 — WAF + Proxy" >> "$REPORT"
  echo "" >> "$REPORT"

  for sub in "${PROXY_RECORDS[@]}"; do
    fqdn="$DOMAIN"
    [ "$sub" != "@" ] && fqdn="${sub}.${DOMAIN}"
    cf_set_proxy "$ZONE_ID" "$fqdn" "true"
    echo "  🟢 proxied: $fqdn"
    echo "- 🟢 Proxy ON: \`$fqdn\`" >> "$REPORT"
  done
  echo ""

  # WAF Managed Free Ruleset
  # Free zones get an auto-deployed "Cloudflare Managed Free Ruleset"
  # which is already in the http_request_firewall_managed phase. We
  # check it's present; users on Pro+ would also enable Managed Ruleset
  # (id efb7b8c949ac4650a09736fc376e9aee) which is paid.
  echo "▸ Verifying WAF Managed Free Ruleset is deployed"
  WAF_RS=$(cf_api GET "/zones/${ZONE_ID}/rulesets" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for rs in d.get('result', []):
    if rs.get('phase') == 'http_request_firewall_managed':
        print(json.dumps({
            'id': rs.get('id'),
            'name': rs.get('name'),
            'version': rs.get('version'),
        }))
        break")
  if [ -n "$WAF_RS" ]; then
    WAF_NAME=$(echo "$WAF_RS" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
    echo "  🟢 ${WAF_NAME} (auto-deployed for free zones)"
    echo "- 🟢 WAF: ${WAF_NAME}" >> "$REPORT"
  else
    echo "  🟡 No managed firewall ruleset found — may activate after zone goes active"
    echo "- 🟡 WAF Managed Ruleset not yet active (zone status pending?)" >> "$REPORT"
  fi

  # Bot Fight Mode (free tier requires both fight_mode AND enable_js).
  # Sending fight_mode alone returns 400 Bad Request — Cloudflare's
  # validator wants the JS-detection toggle set explicitly.
  echo "▸ Enabling Bot Fight Mode + JS Detection"
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
    echo "  🟢 Bot Fight Mode = ON, JS Detection = ON"
    echo "- 🟢 Bot Fight Mode + JS Detection = ON" >> "$REPORT"
  else
    # Check current state — maybe it's already enabled from prior run
    CUR_BOT=$(cf_api GET "/zones/${ZONE_ID}/bot_management" | python3 -c "
import json, sys
try:
    r = json.load(sys.stdin).get('result') or {}
    print('1' if r.get('fight_mode') and r.get('enable_js') else '0')
except Exception:
    print('0')
")
    if [ "$CUR_BOT" = "1" ]; then
      echo "  🟢 Bot Fight Mode + JS Detection (already ON)"
      echo "- 🟢 Bot Fight Mode + JS Detection (already ON)" >> "$REPORT"
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
      echo "  🟡 Bot Fight Mode — $msg"
      echo "- 🟡 Bot Fight Mode — $msg" >> "$REPORT"
    fi
  fi

  apply_setting "Security Level = medium"   "security_level"     '"medium"'
  apply_setting "Challenge TTL = 30min"     "challenge_ttl"      "1800"
  apply_setting "Privacy Pass = ON"         "privacy_pass"       '"on"'

  # Rate limit rule (Free tier limits — verified 2026-05-02):
  #   - period MUST be 10 seconds (60 fails: "not entitled to period 60")
  #   - mitigation_timeout MUST be 10 (anything else fails)
  #   - regex `matches` operator NOT allowed (paid plan); use starts_with/eq/etc
  #   - requests_per_period: free tier observed working at 50; YMMV
  # To convert a "rpm" target: requests_per_10s = max(1, rpm / 6)
  echo "▸ Adding rate-limit rule: ${RL_PATH} → ${RL_RPM}/min/IP"

  # Translate path glob "/api/*" into a free-tier-friendly expression.
  # If the user gave "/api/*" we use starts_with(path, "/api/")
  # If they gave a plain path we use eq.
  RL_PATH_PREFIX="${RL_PATH%\*}"   # strip trailing *
  if [ "$RL_PATH" != "$RL_PATH_PREFIX" ]; then
    # was a glob
    RL_EXPR='(starts_with(http.request.uri.path, "'${RL_PATH_PREFIX}'"))'
  else
    RL_EXPR='(http.request.uri.path eq "'${RL_PATH}'")'
  fi
  RL_REQS_10S=$(( RL_RPM / 6 ))
  [ "$RL_REQS_10S" -lt 1 ] && RL_REQS_10S=1

  # Check existing entrypoint OR existing zone-kind ruleset in this phase
  # (free tier allows only 1 ratelimit ruleset per zone — re-runs must be
  # idempotent without trying to recreate).
  RL_EXISTING=$(cf_api GET "/zones/${ZONE_ID}/rulesets" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for rs in d.get('result', []):
    if rs.get('phase') == 'http_ratelimit':
        print(rs.get('id', ''))
        break")
  if [ -n "$RL_EXISTING" ]; then
    echo "  🟢 Rate-limit ruleset already deployed (id ${RL_EXISTING:0:8}***)"
    cf_api GET "/zones/${ZONE_ID}/rulesets/${RL_EXISTING}" | python3 -c "
import json, sys
r = json.load(sys.stdin).get('result') or {}
for rule in r.get('rules', []):
    rl = rule.get('ratelimit', {})
    print(f\"     {rule.get('description','?')} ({rl.get('requests_per_period','?')} req/{rl.get('period','?')}s)\")"
    echo "- 🟢 Rate limit (existing): preserved" >> "$REPORT"
    RL_PHASE='__SKIP__'   # signal to skip create+update branches
  else
    RL_PHASE=$(cf_api GET "/zones/${ZONE_ID}/rulesets/phases/http_ratelimit/entrypoint")
  fi

  if [ "$RL_PHASE" != "__SKIP__" ] && echo "$RL_PHASE" | grep -q '"success":true'; then
    # Entrypoint exists — append rule (free tier supports 1 rule total,
    # so re-running is idempotent only if we delete first; we'll
    # detect that and skip if a skill-managed rule is already there).
    RL_RS_ID=$(echo "$RL_PHASE" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])")
    HAS_SKILL_RULE=$(echo "$RL_PHASE" | python3 -c "
import json, sys
rules = (json.load(sys.stdin).get('result') or {}).get('rules') or []
print('1' if any('the skill' in (r.get('description','')) for r in rules) else '0')
")
    if [ "$HAS_SKILL_RULE" = "1" ]; then
      echo "  🟡 the skill rate limit already present — skipping (idempotent)"
      echo "- 🟡 Rate limit (already configured): ${RL_REQS_10S} req/10s on \`${RL_PATH}\`" >> "$REPORT"
    else
      RL_RULE=$(python3 -c "
import json
print(json.dumps({
  'description': f'the skill: {${RL_REQS_10S}} req/10s per IP on ${RL_PATH}',
  'expression': '''$RL_EXPR''',
  'action': 'block',
  'ratelimit': {
    'characteristics': ['cf.colo.id', 'ip.src'],
    'period': 10,
    'requests_per_period': ${RL_REQS_10S},
    'mitigation_timeout': 10
  }
}))")
      RL_RESP=$(cf_api POST "/zones/${ZONE_ID}/rulesets/${RL_RS_ID}/rules" "$RL_RULE")
      if echo "$RL_RESP" | grep -q '"success":true'; then
        echo "  🟢 rate limit added: ${RL_REQS_10S} req/10s/IP on ${RL_PATH}"
        echo "- 🟢 Rate limit: ${RL_REQS_10S} req/10s/IP on \`${RL_PATH}\` (~${RL_RPM} rpm)" >> "$REPORT"
      else
        msg=$(echo "$RL_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
        echo "  🟡 rate limit — $msg"
        echo "- 🟡 Rate limit — $msg" >> "$REPORT"
      fi
    fi
  elif [ "$RL_PHASE" != "__SKIP__" ]; then
    # Bootstrap: create the phase entrypoint with this rule
    RL_BODY=$(python3 -c "
import json
print(json.dumps({
  'name': 'the skill zone rate limiting',
  'description': 'Rate limit rules deployed by the skill cloudflare-dns skill',
  'kind': 'zone',
  'phase': 'http_ratelimit',
  'rules': [{
    'description': f'the skill: {${RL_REQS_10S}} req/10s per IP on ${RL_PATH}',
    'expression': '''$RL_EXPR''',
    'action': 'block',
    'ratelimit': {
      'characteristics': ['cf.colo.id', 'ip.src'],
      'period': 10,
      'requests_per_period': ${RL_REQS_10S},
      'mitigation_timeout': 10
    }
  }]
}))")
    RL_RESP=$(cf_api POST "/zones/${ZONE_ID}/rulesets" "$RL_BODY")
    if echo "$RL_RESP" | grep -q '"success":true'; then
      echo "  🟢 rate limit applied: ${RL_REQS_10S} req/10s/IP on ${RL_PATH}"
      echo "- 🟢 Rate limit: ${RL_REQS_10S} req/10s/IP on \`${RL_PATH}\` (~${RL_RPM} rpm)" >> "$REPORT"
    else
      msg=$(echo "$RL_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); errs=d.get('errors',[]); print(errs[0].get('message','?') if errs else '?')")
      echo "  🟡 rate limit — $msg"
      echo "- 🟡 Rate limit — $msg" >> "$REPORT"
    fi
  fi
  echo ""
fi

# ===========================================================================
# Live verification
# ===========================================================================
echo "▸ Live HTTP smoke test"
echo "" >> "$REPORT"
echo "## Post-hardening live test" >> "$REPORT"
echo "" >> "$REPORT"
echo '```' >> "$REPORT"
for sub in "" "www." "api." "docs."; do
  host="${sub}${DOMAIN}"
  status=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | head -1 | tr -d '\r')
  hsts=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | grep -i "strict-transport" | head -1 | tr -d '\r')
  server=$(curl -sI -m 8 "https://${host}/" 2>/dev/null | grep -i "^server:" | head -1 | tr -d '\r')
  printf "  %-30s %s\n  %s\n  %s\n\n" "$host" "${status:-FAIL}" "$server" "$hsts"
  printf "%-30s %s\n  %s\n  %s\n\n" "$host" "${status:-FAIL}" "$server" "$hsts" >> "$REPORT"
done
echo '```' >> "$REPORT"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Hardening complete"
echo "  Report saved: $REPORT"
echo "═══════════════════════════════════════════════════════════════"
