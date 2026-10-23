#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: search.sh <query> [options]

Keyword search over a markdown knowledge base.

Options:
  --type TYPE      Only search pages whose frontmatter type matches
  --limit N        Maximum results (default: 20)
  --root DIR       Knowledge base root (default: $KB_ROOT or ./brain)
  --files-only     Print matching file paths only
  --json           JSON output (requires jq)
  -h, --help       Show this help

Examples:
  search.sh "annual-only pricing"
  search.sh "Jane Doe" --type person
  search.sh "works_at" --files-only
  search.sh "pricing" --json --limit 50

Environment:
  KB_ROOT          Default knowledge base root
EOF
}

die() { echo "error: $*" >&2; exit 2; }

root="${KB_ROOT:-./brain}"
type=""
limit=20
json=0
files_only=0
query=""

while [ $# -gt 0 ]; do
  case "$1" in
    --type) [ $# -ge 2 ] || die "missing value for --type"; type="$2"; shift 2 ;;
    --limit) [ $# -ge 2 ] || die "missing value for --limit"; limit="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || die "missing value for --root"; root="$2"; shift 2 ;;
    --files-only) files_only=1; shift ;;
    --json) json=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) query="${query:+$query }$1"; shift ;;
  esac
done

[ -n "$query" ] || { usage >&2; exit 2; }
[ -d "$root" ] || die "knowledge base not found: $root"
case "$limit" in ''|*[!0-9]*) die "--limit must be a positive integer" ;; esac
[ "$limit" -gt 0 ] || die "--limit must be a positive integer"

command -v rg >/dev/null 2>&1 || die "ripgrep (rg) is required"
if [ -n "$type" ]; then
  case "$type" in *[!a-z0-9-]*) die "--type must be lowercase letters, digits, or hyphens" ;; esac
fi
if [ "$json" -eq 1 ]; then
  command -v jq >/dev/null 2>&1 || die "jq is required for --json"
fi

if [ -n "$type" ]; then
  files=()
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(rg -l --color never "^type:[[:space:]]*[\"']?${type}[\"']?[[:space:]]*$" "$root" --glob '*.md' --glob '*.mdx' || true)

  if [ "${#files[@]}" -eq 0 ]; then
    if [ "$json" -eq 1 ]; then
      printf '[]\n'
    else
      echo "no pages of type '$type' under $root"
    fi
    exit 0
  fi
  search_paths=("${files[@]}")
  glob_args=(--glob '*.md' --glob '*.mdx')
else
  search_paths=("$root")
  glob_args=(--glob '*.md' --glob '*.mdx')
fi

if [ "$json" -eq 1 ]; then
  if [ "$files_only" -eq 1 ]; then
    output=$(rg --color never --files-with-matches "${glob_args[@]}" -- "$query" "${search_paths[@]}" || true)
    printf '%s\n' "$output" | jq -R -s --argjson limit "$limit" \
      'split("\n") | map(select(length > 0)) | .[:$limit] | map({file: .})'
  else
    rg --color never --json "${glob_args[@]}" -- "$query" "${search_paths[@]}" 2>/dev/null \
      | jq -c 'select(.type == "match") | {file: .data.path.text, line: .data.line_number, text: (.data.lines.text | rtrimstr("\n"))}' \
      | awk -v limit="$limit" 'NR <= limit' || true
  fi
else
  if [ "$files_only" -eq 1 ]; then
    output=$(rg --color never --files-with-matches "${glob_args[@]}" -- "$query" "${search_paths[@]}" || true)
  else
    output=$(rg --color never --line-number --no-heading --smart-case "${glob_args[@]}" -- "$query" "${search_paths[@]}" || true)
  fi
  printf '%s\n' "$output" | awk -v limit="$limit" 'NF && NR <= limit'
fi
