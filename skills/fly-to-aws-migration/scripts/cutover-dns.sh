#!/usr/bin/env bash
# Phase 4+5 cutover: atomic DNS flip via Cloudflare API.
# Cloudflare proxied records = <5s propagation.
#
# Usage:
#   ./cutover-dns.sh <hostname> <new-target> [--dry-run]
# Example:
#   ./cutover-dns.sh api.example.com myalb-1234.us-east-1.elb.amazonaws.com

set -euo pipefail

HOSTNAME="${1:?hostname required, e.g. api.example.com}"
NEW_TARGET="${2:?new target DNS name required}"
DRY_RUN="${3:-}"

: "${CLOUDFLARE_EMAIL:?CLOUDFLARE_EMAIL env var required}"
: "${CLOUDFLARE_GLOBAL_API_KEY:?CLOUDFLARE_GLOBAL_API_KEY env var required}"
: "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID env var required}"

API="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID"

echo "=== Pre-cutover state ==="
RECORD=$(curl -sS -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
  "$API/dns_records?name=$HOSTNAME" \
  | jq -r '.result[0]')

RECORD_ID=$(echo "$RECORD" | jq -r '.id')
OLD_TYPE=$(echo "$RECORD" | jq -r '.type')
OLD_TARGET=$(echo "$RECORD" | jq -r '.content')
PROXIED=$(echo "$RECORD" | jq -r '.proxied')

if [ "$RECORD_ID" = "null" ]; then
  echo "🔴 No DNS record found for $HOSTNAME"
  exit 1
fi

echo "  Record ID: $RECORD_ID"
echo "  Type: $OLD_TYPE"
echo "  Current target: $OLD_TARGET"
echo "  Proxied: $PROXIED"
echo "  New target: $NEW_TARGET"
echo ""

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "🟡 Dry run — no changes made"
  exit 0
fi

read -p "Confirm cutover? (yes/NO): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted"
  exit 1
fi

echo ""
echo "=== Pre-flight health check on new target ==="
# Test directly via Host header
NEW_TARGET_RESPONSE=$(curl -sS -o /dev/null -k -H "Host: $HOSTNAME" -w "%{http_code}" \
  "https://$NEW_TARGET/health" || echo "FAIL")

echo "  $NEW_TARGET → /health: $NEW_TARGET_RESPONSE"

if [ "$NEW_TARGET_RESPONSE" != "200" ]; then
  echo "🔴 New target /health did not return 200. Aborting."
  echo "    Manually check before retrying."
  exit 1
fi

echo ""
echo "=== Saving rollback info ==="
ROLLBACK_FILE="/tmp/rollback-$HOSTNAME-$(date +%Y%m%d-%H%M%S).json"
echo "$RECORD" > "$ROLLBACK_FILE"
echo "  Rollback data saved to $ROLLBACK_FILE"

echo ""
echo "=== Flipping DNS ==="
RESULT=$(curl -sS -X PATCH \
  -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
  -H "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
  -H "Content-Type: application/json" \
  "$API/dns_records/$RECORD_ID" \
  -d "{\"content\": \"$NEW_TARGET\", \"comment\": \"Cutover $(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")

SUCCESS=$(echo "$RESULT" | jq -r '.success')
if [ "$SUCCESS" != "true" ]; then
  echo "🔴 Cutover failed:"
  echo "$RESULT" | jq -r '.errors'
  exit 1
fi

echo "🟢 DNS flipped. Verifying propagation..."

echo ""
echo "=== Verifying (30s window) ==="
START_TIME=$(date +%s)
for i in $(seq 1 30); do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "https://$HOSTNAME/health" || echo "FAIL")
  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "  T+${ELAPSED}s: HTTP $STATUS"

  if [ "$STATUS" = "200" ]; then
    echo "🟢 Cutover successful at T+${ELAPSED}s"
    break
  fi
  sleep 1
done

echo ""
echo "=== Done. ==="
echo ""
echo "🔴 ROLLBACK COMMAND (save this):"
echo "curl -X PATCH \\"
echo "  -H \"X-Auth-Email: \$CLOUDFLARE_EMAIL\" -H \"X-Auth-Key: \$CLOUDFLARE_GLOBAL_API_KEY\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  \"$API/dns_records/$RECORD_ID\" \\"
echo "  -d '{\"content\":\"$OLD_TARGET\"}'"
echo ""
echo "🟢 Monitor for 10 min minimum before destroying Fly resources."
