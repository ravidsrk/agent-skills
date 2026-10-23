#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scan.sh <url> [options]

Audit a landing page with the public slop-detect engine.

Options:
  --design         Include DESIGN.md / token compliance
  --aeo            Run the AEO readiness audit
  --fix            Generate a copy-pasteable fix prompt
  --craft          Include the craft-floor checks (CLI mode)
  --local          Use the local CLI (required for localhost/private pages)
  --json           Print raw JSON (hosted API mode)
  --api-url URL    Override the hosted API base (default: https://slop-detect.com)
  -h, --help       Show this help

Examples:
  scan.sh https://example.com --design
  scan.sh https://example.com --design --aeo
  scan.sh http://localhost:3000 --local --design

Environment:
  SLOP_DETECT_API_URL   Hosted API base URL
EOF
}

url=""
design=0
aeo=0
fix=0
craft=0
local=0
json=0
api_url="${SLOP_DETECT_API_URL:-https://slop-detect.com}"

while [ $# -gt 0 ]; do
  case "$1" in
    --design) design=1; shift ;;
    --aeo) aeo=1; shift ;;
    --fix) fix=1; shift ;;
    --craft) craft=1; shift ;;
    --local) local=1; shift ;;
    --json) json=1; shift ;;
    --api-url) [ $# -ge 2 ] || { echo "missing value for --api-url" >&2; exit 2; }; api_url="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$url" ] || { echo "only one URL is supported" >&2; exit 2; }; url="$1"; shift ;;
  esac
done

if [ -z "$url" ]; then
  usage >&2
  exit 2
fi

if [ "$local" -eq 1 ]; then
  args=("$url")
  [ "$craft" -eq 1 ] && args+=(--craft)
  [ "$aeo" -eq 1 ] && args+=(--aeo)
  [ "$design" -eq 1 ] && args+=(--design-md auto)
  [ "$fix" -eq 1 ] && args+=(--fix-prompt)
  exec npx -y slop-detect "${args[@]}"
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

if [ "$fix" -eq 1 ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
  body=$(jq -n --arg url "$url" '{url:$url}')
  response=$(curl -sS -X POST "$api_url/api/fix-prompt" \
    -H 'Content-Type: application/json' \
    -d "$body") || { echo "request failed" >&2; exit 1; }
  if printf '%s' "$response" | jq -e 'type == "object" and ((.success == false) or (.error != null))' >/dev/null 2>&1; then
    printf '%s\n' "$response" | jq -r '"Error: " + ((.error // "unknown")|tostring) + (if .message then " — " + .message else "" end)' >&2
    exit 1
  fi
  printf '%s\n' "$response"
  exit 0
fi

aeo_body=$(jq -n --arg url "$url" '{url:$url}')
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }
if [ "$aeo" -eq 1 ] && [ "$design" -eq 0 ]; then
  response=$(curl -sS -X POST "$api_url/api/aeo" \
    -H 'Content-Type: application/json' \
    -d "$aeo_body") || { echo "request failed" >&2; exit 1; }
else
  axes='["design","copy"]'
  body=$(jq -n --arg url "$url" --argjson axes "$axes" --argjson designMd "$([ "$design" -eq 1 ] && echo true || echo false)" \
    '{url:$url, axes:$axes, designMd:$designMd}')
  response=$(curl -sS -X POST "$api_url/api/scan" \
    -H 'Content-Type: application/json' \
    -d "$body") || { echo "request failed" >&2; exit 1; }
  if [ "$aeo" -eq 1 ]; then
    aeo_response=$(curl -sS -X POST "$api_url/api/aeo" \
      -H 'Content-Type: application/json' \
      -d "$aeo_body") || { echo "AEO request failed" >&2; exit 1; }
    if printf '%s' "$aeo_response" | jq -e '.score != null' >/dev/null 2>&1; then
      response=$(jq -n --argjson scan "$response" --argjson aeo "$aeo_response" '$scan + {aeo:$aeo}')
    else
      response=$(jq -n --argjson scan "$response" --argjson aeoErr "$aeo_response" '$scan + {aeoError:$aeoErr}')
    fi
  fi
fi

if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
  echo "Error: scan returned a non-JSON response" >&2
  printf '%s\n' "$response" | head -c 500 >&2
  echo >&2
  exit 1
fi

error_text=$(printf '%s' "$response" | jq -r 'if (.success == false) or (.error != null) then ((.error // "unknown")|tostring) + (if .message then ": " + .message else "" end) else empty end')
aeo_error_text=$(printf '%s' "$response" | jq -r '.aeoError.error // empty' 2>/dev/null || true)

if [ "$json" -eq 1 ]; then
  printf '%s\n' "$response" | jq .
else
  printf '%s\n' "$response" | jq -r '
    if (.success == false) or (.error != null) then
      "Error: " + ((.error // "unknown error")|tostring) + (if .message then " — " + .message else "" end)
    else
      (.data // .) as $d |
      ($d.axes.design // $d.design) as $design |
      ($d.axes.copy // $d.copy) as $copy |
      ($d.axes.system // $d.system) as $system |
      ($d.axes.aeo // $d.aeo // (if $d.axis == "aeo" then $d else null end)) as $aeo |
      ($d.axes.craft // $d.craft) as $craft |
      (($design.patterns // []) + ($copy.patterns // []) | map(select(.triggered))) as $triggered |
      [
        ($d.url // empty),
        (if $design then "Design: " + (($design.tier // "?")|tostring) + " (" + (($design.score // "?")|tostring) + ", grade " + (($design.grade // "?")|tostring) + ")" else empty end),
        (if $copy then "Copy: " + (($copy.tier // "?")|tostring) + " (" + (($copy.score // "?")|tostring) + ", grade " + (($copy.grade // "?")|tostring) + ")" else empty end),
        (if $system then "System: " + (($system.tier // "?")|tostring) + " (" + (($system.score // "?")|tostring) + ")" else empty end),
        (if $aeo then "AEO: " + (($aeo.tier // "?")|tostring) + " (" + (($aeo.score // "?")|tostring) + ")" else empty end),
        (if $d.aeoError then "AEO error: " + (($d.aeoError.error // "unknown")|tostring) else empty end),
        (if $craft then "Craft floor: " + (($craft.score // "?")|tostring) else empty end),
        ($d.verdict // empty),
        (if ($triggered|length) > 0 then "Triggered patterns:" else empty end),
        ($triggered[] | "  - " + (.id // "?") + " (weight " + ((.weight // 0)|tostring) + "): " + (.label // .short // ""))
      ] | .[]
    end'
fi

if [ -n "$error_text" ]; then
  echo "Error: $error_text" >&2
  exit 1
fi
if [ -n "$aeo_error_text" ]; then
  echo "AEO error: $aeo_error_text" >&2
  exit 1
fi
