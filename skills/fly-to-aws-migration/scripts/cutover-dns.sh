#!/usr/bin/env bash
# Phase 4+5 (API) and Phase 6 (static sites) cutover:
# atomic DNS flip via Cloudflare API. Cloudflare proxied records = <5s propagation.
#
# Usage:
#   ./cutover-dns.sh <hostname> <new-target> [--dry-run]
# Example:
#   ./cutover-dns.sh api.example.com myalb-1234.us-east-1.elb.amazonaws.com
#
# Requires (scoped token strongly preferred):
#   CLOUDFLARE_API_TOKEN  Zone:DNS:Edit on the target zone
#   CLOUDFLARE_ZONE_ID    the zone id
#
# Legacy (deprecated) fallback if CLOUDFLARE_API_TOKEN unset:
#   CLOUDFLARE_EMAIL + CLOUDFLARE_GLOBAL_API_KEY

set -euo pipefail

HOSTNAME="${1:?hostname required, e.g. api.example.com}"
NEW_TARGET="${2:?new target DNS name required}"
DRY_RUN="${3:-}"

: "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID env var required}"

AUTH_HEADER=()
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
  AUTH_HEADER=("-H" "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
elif [ -n "${CLOUDFLARE_EMAIL:-}" ] && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ]; then
  AUTH_HEADER=("-H" "X-Auth-Email: $CLOUDFLARE_EMAIL" "-H" "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY")
  echo "🟡 Using legacy Cloudflare global API key. Prefer CLOUDFLARE_API_TOKEN." >&2
else
  echo "🔴 Set CLOUDFLARE_API_TOKEN (preferred) or CLOUDFLARE_EMAIL + CLOUDFLARE_GLOBAL_API_KEY." >&2
  exit 1
fi

API="https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID"

# Small helpers ---------------------------------------------------------------

cf_api() {
  # Wrap curl with -f so 4xx/5xx exit non-zero, and validate JSON `.success`.
  # Args: METHOD URL [DATA]
  local method="$1" url="$2" data="${3:-}"
  local response
  if [ -n "$data" ]; then
    response=$(curl -sSf -X "$method" "${AUTH_HEADER[@]}" \
      -H "Content-Type: application/json" "$url" -d "$data")
  else
    response=$(curl -sSf -X "$method" "${AUTH_HEADER[@]}" "$url")
  fi
  local success
  success=$(echo "$response" | jq -r '.success // false')
  if [ "$success" != "true" ]; then
    echo "🔴 Cloudflare API returned success=false:" >&2
    echo "$response" | jq -r '.errors // "(no errors block)"' >&2
    return 1
  fi
  echo "$response"
}

# 1. Read current record ------------------------------------------------------

echo "=== Pre-cutover state ==="
if ! LIST_RESP=$(cf_api GET "$API/dns_records?name=$HOSTNAME"); then
  echo "🔴 Failed to look up $HOSTNAME in zone $CLOUDFLARE_ZONE_ID" >&2
  exit 1
fi

RECORD=$(echo "$LIST_RESP" | jq -r '.result[0] // empty')
if [ -z "$RECORD" ] || [ "$RECORD" = "null" ]; then
  echo "🔴 No DNS record found for $HOSTNAME" >&2
  exit 1
fi

RECORD_ID=$(echo "$RECORD" | jq -r '.id')
OLD_TYPE=$(echo "$RECORD" | jq -r '.type')
OLD_TARGET=$(echo "$RECORD" | jq -r '.content')
PROXIED=$(echo "$RECORD" | jq -r '.proxied')

echo "  Record ID: $RECORD_ID"
echo "  Type: $OLD_TYPE"
echo "  Current target: $OLD_TARGET"
echo "  Proxied: $PROXIED"
echo "  New target: $NEW_TARGET"
echo ""

# Refuse to cut over a non-proxied record — the <5s propagation guarantee only
# holds for orange-cloud (proxied=true) records.
if [ "$PROXIED" != "true" ]; then
  echo "🔴 Record $HOSTNAME is NOT proxied (orange cloud). Aborting." >&2
  echo "   The atomic <5s cutover guarantee only applies to proxied records." >&2
  echo "   Enable Cloudflare proxy on the record first, then re-run." >&2
  exit 1
fi

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "🟡 Dry run — no changes made"
  exit 0
fi

read -r -p "Confirm cutover? (yes/NO): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted"
  exit 1
fi

# 2. Pre-flight health check on new target -----------------------------------

echo ""
echo "=== Pre-flight health check on new target ==="
# -k because the ALB DNS presents a cert for the real hostname, not the ALB.
# We're inside our own control plane, hitting our own ALB with a Host header.
NEW_TARGET_RESPONSE=$(curl -sS -o /dev/null -k -H "Host: $HOSTNAME" -w "%{http_code}" \
  "https://$NEW_TARGET/health" || echo "FAIL")

echo "  $NEW_TARGET → /health: $NEW_TARGET_RESPONSE"

if [ "$NEW_TARGET_RESPONSE" != "200" ]; then
  echo "🔴 New target /health did not return 200. Aborting." >&2
  echo "    Manually check before retrying." >&2
  exit 1
fi

# 3. Save rollback info ------------------------------------------------------

echo ""
echo "=== Saving rollback info ==="
ROLLBACK_FILE="/tmp/rollback-$HOSTNAME-$(date +%Y%m%d-%H%M%S).json"
echo "$RECORD" > "$ROLLBACK_FILE"
echo "  Rollback data saved to $ROLLBACK_FILE"

# 4. Flip DNS ----------------------------------------------------------------

echo ""
echo "=== Flipping DNS ==="
CUTOVER_COMMENT="Cutover $(date -u +%Y-%m-%dT%H:%M:%SZ)"
PATCH_BODY=$(jq -n \
  --arg content "$NEW_TARGET" \
  --arg comment "$CUTOVER_COMMENT" \
  '{content: $content, proxied: true, comment: $comment}')

if ! cf_api PATCH "$API/dns_records/$RECORD_ID" "$PATCH_BODY" > /dev/null; then
  echo "🔴 PATCH failed. Zone likely unchanged." >&2
  exit 1
fi

echo "🟢 DNS flipped. Verifying propagation..."

# 5. Verify ------------------------------------------------------------------

echo ""
echo "=== Verifying (30s window) ==="
START_TIME=$(date +%s)
CUTOVER_OK=0
for _ in $(seq 1 30); do
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "https://$HOSTNAME/health" || echo "FAIL")
  ELAPSED=$(( $(date +%s) - START_TIME ))
  echo "  T+${ELAPSED}s: HTTP $STATUS"

  if [ "$STATUS" = "200" ]; then
    echo "🟢 Cutover successful at T+${ELAPSED}s"
    CUTOVER_OK=1
    break
  fi
  sleep 1
done

echo ""
echo "🔴 ROLLBACK COMMAND (save this):"
cat <<ROLLBACK
curl -sSf -X PATCH \\
  -H "Authorization: Bearer \$CLOUDFLARE_API_TOKEN" \\
  -H "Content-Type: application/json" \\
  "$API/dns_records/$RECORD_ID" \\
  -d '{"content":"$OLD_TARGET","proxied":true}'
ROLLBACK

if [ "$CUTOVER_OK" -ne 1 ]; then
  echo "" >&2
  echo "🔴 Cutover verification FAILED — https://$HOSTNAME/health never returned HTTP 200 within 30s." >&2
  echo "   DNS was flipped to $NEW_TARGET. Use the rollback command above if needed." >&2
  exit 1
fi

echo ""
echo "=== Done. ==="
echo ""
echo "🟢 Monitor for 10 min minimum before destroying Fly resources."
