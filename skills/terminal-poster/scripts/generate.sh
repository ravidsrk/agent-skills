#!/bin/bash
# Generate a terminal-poster via Nano Banana Pro (OpenRouter).
# Usage: generate.sh <prompt-file> <output-png> [--model pro|2|legacy]
#
# Env required: $OPENROUTER_API_KEY
#
# Examples:
#   bash generate.sh /tmp/prompt.txt ./out.png
#   bash generate.sh /tmp/draft.txt /tmp/draft.png --model 2   # cheaper draft tier

set -e

PROMPT_FILE="${1:-}"
OUT_PATH="${2:-}"
MODEL_FLAG="${3:-}"

if [ -z "$PROMPT_FILE" ] || [ -z "$OUT_PATH" ]; then
  echo "Usage: $0 <prompt-file> <output-png> [--model pro|2|legacy]" >&2
  exit 1
fi
[ -f "$PROMPT_FILE" ] || { echo "ERR: prompt file not found: $PROMPT_FILE" >&2; exit 1; }
[ -n "$OPENROUTER_API_KEY" ] || { echo "ERR: \$OPENROUTER_API_KEY not set" >&2; exit 1; }

# Pick model
MODEL="google/gemini-3-pro-image-preview"  # Nano Banana Pro = default
if [ "$MODEL_FLAG" = "--model" ] && [ "$4" = "2" ]; then
  MODEL="google/gemini-3.1-flash-image-preview"  # Nano Banana 2 = draft tier
elif [ "$MODEL_FLAG" = "--model" ] && [ "$4" = "legacy" ]; then
  MODEL="google/gemini-2.5-flash-image-preview"  # original Nano Banana
fi

# Build request body
PROMPT_JSON=$(cat "$PROMPT_FILE" | jq -Rs .)
BODY_FILE=$(mktemp)
cat > "$BODY_FILE" <<EOF
{
  "model": "$MODEL",
  "modalities": ["image", "text"],
  "messages": [{"role": "user", "content": $PROMPT_JSON}]
}
EOF

# Call API
RESP_FILE=$(mktemp)
echo "[terminal-poster] model=$MODEL  output=$OUT_PATH" >&2
echo "[terminal-poster] calling OpenRouter..." >&2

curl -s https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"$BODY_FILE" \
  -o "$RESP_FILE"

# Check for error
ERR=$(jq -r '.error.message // empty' "$RESP_FILE" 2>/dev/null)
if [ -n "$ERR" ]; then
  echo "[terminal-poster] ERROR: $ERR" >&2
  rm -f "$BODY_FILE"
  exit 2
fi

# Decode image (Nano Banana sometimes returns PNG, sometimes JPEG — sniff and report)
IMG_URL=$(jq -r '.choices[0].message.images[0].image_url.url // empty' "$RESP_FILE")
if [ -z "$IMG_URL" ]; then
  echo "[terminal-poster] ERROR: no image in response. Full response:" >&2
  cat "$RESP_FILE" >&2
  rm -f "$BODY_FILE" "$RESP_FILE"
  exit 3
fi

# Extract mime type and base64 payload
MIME=$(printf '%s' "$IMG_URL" | sed -n 's|^data:\(image/[^;]*\);base64,.*|\1|p')
echo "$IMG_URL" | sed 's|^data:image/[^;]*;base64,||' | base64 -d > "$OUT_PATH"

SIZE=$(wc -c < "$OUT_PATH" | tr -d " ")   # portable (GNU stat -c fails on macOS)
echo "[terminal-poster] ✅ wrote $OUT_PATH ($SIZE bytes, mime=$MIME)" >&2

# Clean up
rm -f "$BODY_FILE" "$RESP_FILE"

# If the user gave a .png path but the model returned JPEG, leave a warning
if [[ "$OUT_PATH" == *.png ]] && [ "$MIME" = "image/jpeg" ]; then
  echo "[terminal-poster] ⚠️  File saved as $OUT_PATH but actual format is JPEG. Some preview tools may complain." >&2
fi
if [[ "$OUT_PATH" == *.jpg ]] && [ "$MIME" = "image/png" ]; then
  echo "[terminal-poster] ⚠️  File saved as $OUT_PATH but actual format is PNG. Some preview tools may complain." >&2
fi
