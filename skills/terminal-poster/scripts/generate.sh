#!/usr/bin/env bash
# Generate a terminal-poster via Nano Banana Pro (OpenRouter).
# Usage: generate.sh <prompt-file> <output-png> [--model pro|2|legacy]
#
# Env required: $OPENROUTER_API_KEY
#
# Examples:
#   bash generate.sh /tmp/prompt.txt ./out.png
#   bash generate.sh /tmp/draft.txt /tmp/draft.png --model 2   # cheaper draft tier
#
# Model slugs are OpenRouter identifiers. Verify current names at:
#   https://openrouter.ai/models?q=gemini+image
# If OpenRouter renames a slug, the API will return a "model not found"
# error and this script will surface it. Update the MODEL_* constants
# below in that case.

set -euo pipefail

# --- Args ---
PROMPT_FILE="${1:-}"
OUT_PATH="${2:-}"
MODEL_FLAG="${3:-}"
MODEL_VAL="${4:-}"

usage() {
  echo "Usage: $0 <prompt-file> <output-png> [--model pro|2|legacy]" >&2
  exit 1
}

if [ -z "$PROMPT_FILE" ] || [ -z "$OUT_PATH" ]; then
  usage
fi
[ -f "$PROMPT_FILE" ] || { echo "ERR: prompt file not found: $PROMPT_FILE" >&2; exit 1; }
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "ERR: \$OPENROUTER_API_KEY not set" >&2; exit 1; }

# --- Pick model ---
# Verify slugs at https://openrouter.ai/models?q=gemini+image
MODEL_PRO="google/gemini-3-pro-image-preview"          # Nano Banana Pro (default)
MODEL_2="google/gemini-3.1-flash-image-preview"        # Nano Banana 2 (draft tier)
MODEL_LEGACY="google/gemini-2.5-flash-image-preview"   # original Nano Banana

MODEL="$MODEL_PRO"
if [ -n "$MODEL_FLAG" ]; then
  if [ "$MODEL_FLAG" != "--model" ]; then
    echo "ERR: unknown flag: $MODEL_FLAG" >&2
    usage
  fi
  case "$MODEL_VAL" in
    pro|"") MODEL="$MODEL_PRO" ;;
    2)      MODEL="$MODEL_2" ;;
    legacy) MODEL="$MODEL_LEGACY" ;;
    *)
      echo "ERR: unknown --model value: $MODEL_VAL (want pro|2|legacy)" >&2
      exit 1
      ;;
  esac
fi

# --- Secret-scrubbing helper (used in every error dump) ---
scrub_secrets() {
  # Redact the API key if it ever gets echoed back.
  sed -e "s|${OPENROUTER_API_KEY}|[REDACTED_OPENROUTER_API_KEY]|g"
}

# --- Build request body ---
PROMPT_JSON=$(jq -Rs . < "$PROMPT_FILE")
BODY_FILE=$(mktemp -t terminal-poster-body.XXXXXX)
RESP_FILE=$(mktemp -t terminal-poster-resp.XXXXXX)
trap 'rm -f "$BODY_FILE" "$RESP_FILE"' EXIT

cat > "$BODY_FILE" <<EOF
{
  "model": "$MODEL",
  "modalities": ["image", "text"],
  "messages": [{"role": "user", "content": $PROMPT_JSON}]
}
EOF

# --- Call API with basic retry on 429/5xx ---
echo "[terminal-poster] model=$MODEL  output=$OUT_PATH" >&2
echo "[terminal-poster] calling OpenRouter..." >&2

HTTP_CODE="000"
ATTEMPT=0
MAX_ATTEMPTS=3
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT+1))
  # curl -sS: quiet but errors show. -w '%{http_code}' captures status.
  # -o writes body to $RESP_FILE. `|| true` prevents `set -e` abort so we can
  # inspect the code and decide whether to retry.
  HTTP_CODE=$(curl -sS -w '%{http_code}' -o "$RESP_FILE" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -H "Content-Type: application/json" \
    -X POST https://openrouter.ai/api/v1/chat/completions \
    -d @"$BODY_FILE" || echo "000")
  case "$HTTP_CODE" in
    2*)
      break
      ;;
    429|500|502|503|504|000)
      if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        SLEEP=$((ATTEMPT*2))
        echo "[terminal-poster] HTTP $HTTP_CODE - retrying in ${SLEEP}s (attempt $ATTEMPT/$MAX_ATTEMPTS)" >&2
        sleep $SLEEP
      fi
      ;;
    *)
      echo "[terminal-poster] ERROR: HTTP $HTTP_CODE - response:" >&2
      scrub_secrets < "$RESP_FILE" >&2 || true
      exit 2
      ;;
  esac
done

case "$HTTP_CODE" in
  2*) ;;
  *)
    echo "[terminal-poster] ERROR: HTTP $HTTP_CODE after $ATTEMPT attempt(s). Response:" >&2
    scrub_secrets < "$RESP_FILE" >&2 || true
    exit 2
    ;;
esac

# --- Structured JSON error field ---
ERR=$(jq -r '.error.message // empty' "$RESP_FILE" 2>/dev/null || true)
if [ -n "$ERR" ]; then
  echo "[terminal-poster] ERROR: $ERR" >&2
  exit 2
fi

# --- Decode image (Nano Banana sometimes returns PNG, sometimes JPEG - sniff and report) ---
IMG_URL=$(jq -r '.choices[0].message.images[0].image_url.url // empty' "$RESP_FILE")
if [ -z "$IMG_URL" ]; then
  echo "[terminal-poster] ERROR: no image in response. Full response:" >&2
  scrub_secrets < "$RESP_FILE" >&2
  exit 3
fi

# Extract mime type and base64 payload
MIME=$(printf '%s' "$IMG_URL" | sed -n 's|^data:\(image/[^;]*\);base64,.*|\1|p')
printf '%s' "$IMG_URL" | sed 's|^data:image/[^;]*;base64,||' | base64 -d > "$OUT_PATH"

# wc -c is portable across GNU and BSD; stat flags differ (-c%s vs -f%z).
SIZE=$(wc -c < "$OUT_PATH" | tr -d ' ')
echo "[terminal-poster] wrote $OUT_PATH ($SIZE bytes, mime=$MIME)" >&2

# --- Mime-vs-extension mismatch warning ---
if [[ "$OUT_PATH" == *.png ]] && [ "$MIME" = "image/jpeg" ]; then
  echo "[terminal-poster] WARNING: File saved as $OUT_PATH but actual format is JPEG. Some preview tools may complain." >&2
fi
if [[ "$OUT_PATH" == *.jpg ]] && [ "$MIME" = "image/png" ]; then
  echo "[terminal-poster] WARNING: File saved as $OUT_PATH but actual format is PNG. Some preview tools may complain." >&2
fi
