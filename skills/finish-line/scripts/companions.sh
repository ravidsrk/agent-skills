#!/usr/bin/env bash
# companions.sh — community skill packs as optional helpers for finish-line:
# find them, pin them, and fence off the parts that would break the run.
#
#   companions.sh detect [repo]       write <repo>/.finish/companions.json: the installed skill that
#                                     fills each slot (a protocol step), plus tools such as gstack's browser
#   companions.sh show [repo]         print that file with the step each slot belongs to
#   companions.sh policy [--runner]   settings JSON denying every pack's asking, planning, publishing
#                                     and merging skills; --runner (what finish.sh passes with --settings)
#                                     also denies gstack's unprefixed names and turns hooks off
#   companions.sh settings [repo]     merge the non-runner policy into the repo's
#                                     .claude/settings.local.json, when finish-line created that file
#   companions.sh install [pack…]     install packs pinned to reviewed commits, then detect if run in a repo.
#                                     Default: the recommended packs (superpowers agent-skills);
#                                     also offered: mattpocock-skills gstack
#   companions.sh list                the catalog: packs, pins, licenses, slots
#
# Env:
#   FINISH_COMPANIONS=off   detect records no companions (the protocol then uses its built-in steps)
#   FINISH_KEEP_HOOKS=1     policy --runner leaves hooks on
#   CLAUDE_CONFIG_DIR       Claude Code's config dir (default ~/.claude); skills-dir packs live in its skills/
#
# Companions are tools, never authorities: the ledger, verify.sh, tamper.sh and the verifier
# decide what is done. Data: companions/catalog.json and companions/.claude-plugin/marketplace.json.

# shellcheck disable=SC2016  # $names inside single quotes are jq variables, not shell
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$HERE/lib.sh"
fl_need jq

CAT="$SKILL/companions/catalog.json"
MKT="$SKILL/companions"
MKT_NAME="$(jq -r .name "$MKT/.claude-plugin/marketplace.json" 2>/dev/null)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
[[ -f "$CAT" ]] || fl_die "missing $CAT"

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }
cat_get() { jq -r "$@" "$CAT"; }

# Frontmatter helpers (first --- block of a SKILL.md).
fm_name() { awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { exit } f && /^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/["\047]/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1"; }
fm_user_only() { awk 'NR == 1 && /^---/ { f = 1; next } f && /^---/ { exit } f && /^disable-model-invocation:[[:space:]]*true/ { hit = 1 } END { exit !hit }' "$1"; }

PLUGINS='[]'
load_plugins() { # every installed plugin: [{name, id, version, enabled, path}]
  command -v claude >/dev/null 2>&1 || { PLUGINS='[]'; return 0; }
  PLUGINS="$(claude plugin list --json 2>/dev/null \
    | jq -c '[.[]? | {name: (.id | split("@")[0]), id, version, enabled: (.enabled == true), path: .installPath}]' 2>/dev/null)" \
    || PLUGINS='[]'
  [[ -n "$PLUGINS" ]] || PLUGINS='[]'
}

plugin_skill() { # <install path> <skill> → its name, if a model-invocable SKILL.md exists there
  local f n
  # Shallowest match wins, so a test fixture deeper in the plugin can't stand in for the real skill.
  f="$(find "$1" \( -name node_modules -o -name .git \) -prune -o -type f -name SKILL.md \
        \( -path "*/skills/$2/SKILL.md" -o -path "*/skills/*/$2/SKILL.md" \) -print 2>/dev/null \
        | awk -F/ '{ print NF "\t" $0 }' | sort -n | head -1 | cut -f2-)"
  [[ -n "$f" ]] || return 1
  fm_user_only "$f" && return 1
  n="$(fm_name "$f")"
  printf '%s' "${n:-$2}"
}

dir_skill() { # <pack> <skill> → the name a skills-dir pack registered it under (gstack: gstack-<skill> or <skill>)
  local base dirname prefix n f t nm
  dirname="$(cat_get --arg p "$1" '.packs[$p].dir')"; base="$SKILLS_DIR/$dirname"
  prefix="$(cat_get --arg p "$1" '.packs[$p].prefix // ""')"
  [[ -f "$base/$2/SKILL.md" ]] || return 1
  for n in "$prefix$2" "$2"; do
    f="$SKILLS_DIR/$n/SKILL.md"
    [[ -f "$f" ]] || continue
    t="$(readlink "$f" 2>/dev/null || true)"
    case "$t" in "$base"/*|*/"$dirname"/*|"$dirname"/*) ;; *) continue ;; esac   # must belong to the pack
    fm_user_only "$f" && return 1
    nm="$(fm_name "$f")"
    printf '%s' "${nm:-$n}"
    return 0
  done
  return 1
}

resolve() { # <pack> <skill> → invocation name, if installed, enabled, model-invocable and not denied
  local pack="$1" skill="$2" plugin ip n
  cat_get -e --arg p "$pack" --arg s "$skill" '.packs[$p].deny | index($s)' >/dev/null 2>&1 && return 1
  case "$(cat_get --arg p "$pack" '.packs[$p].type // ""')" in
    plugin)
      plugin="$(cat_get --arg p "$pack" '.packs[$p].plugin')"
      ip="$(jq -r --arg p "$plugin" '[.[] | select(.name == $p and .enabled)][0].path // empty' <<< "$PLUGINS")"
      [[ -n "$ip" && -d "$ip" ]] || return 1
      n="$(plugin_skill "$ip" "$skill")" || return 1
      printf '%s:%s' "$plugin" "$n" ;;
    skills-dir)
      dir_skill "$pack" "$skill" ;;
    *) return 1 ;;
  esac
}

pack_version() { # <pack> → "<id> <version>" or "<version> (<sha>)", empty when absent
  local pack="$1" plugin base v
  case "$(cat_get --arg p "$pack" '.packs[$p].type // ""')" in
    plugin)
      plugin="$(cat_get --arg p "$pack" '.packs[$p].plugin')"
      jq -r --arg p "$plugin" '[.[] | select(.name == $p and .enabled)][0] | if . then "\(.id) \(.version)" else empty end' <<< "$PLUGINS" ;;
    skills-dir)
      base="$SKILLS_DIR/$(cat_get --arg p "$pack" '.packs[$p].dir')"
      [[ -f "$base/SKILL.md" ]] || return 0
      v="$(tr -d '[:space:]' < "$base/VERSION" 2>/dev/null)"
      printf '%s (%s)' "${v:-unknown}" "$(git -C "$base" rev-parse --short HEAD 2>/dev/null || echo 'no git')" ;;
  esac
}

detect() { # <repo root>
  local root="$1" mode="${FINISH_COMPANIONS:-auto}" slots='{}' tools='{}' packs='{}' slot pack skill val name path v
  [[ "$mode" == off ]] || load_plugins
  while IFS= read -r slot; do
    val=""
    if [[ "$mode" != off ]]; then
      while IFS=$'\t' read -r pack skill; do
        if name="$(resolve "$pack" "$skill")" && [[ -n "$name" ]]; then val="$name"; break; fi
      done < <(cat_get --arg s "$slot" '.slots[$s].use[] | "\(.pack)\t\(.skill)"')
    fi
    slots="$(jq -c --arg k "$slot" --arg v "$val" '. + {($k): (if $v == "" then null else $v end)}' <<< "$slots")"
  done < <(cat_get '.slots | keys_unsorted[]')
  while IFS=$'\t' read -r name pack path; do
    val=""
    if [[ "$mode" != off ]]; then
      v="$SKILLS_DIR/$(cat_get --arg p "$pack" '.packs[$p].dir')/$path"
      [[ -x "$v" ]] && val="$v"
    fi
    tools="$(jq -c --arg k "$name" --arg v "$val" '. + {($k): (if $v == "" then null else $v end)}' <<< "$tools")"
  done < <(cat_get '.tools | to_entries[] | "\(.key)\t\(.value.pack)\t\(.value.path)"')
  if [[ "$mode" != off ]]; then
    while IFS= read -r pack; do
      v="$(pack_version "$pack")"
      [[ -z "$v" ]] || packs="$(jq -c --arg k "$pack" --arg v "$v" '. + {($k): $v}' <<< "$packs")"
    done < <(cat_get '.packs | keys_unsorted[]')
  fi
  mkdir -p "$root/.finish"
  jq -n --arg at "$(fl_now)" --arg mode "$mode" --argjson slots "$slots" --argjson tools "$tools" --argjson packs "$packs" \
    '{generated_by: "finish-line scripts/companions.sh detect", at: $at, mode: $mode, slots: $slots, tools: $tools, packs: $packs}' \
    > "$root/.finish/companions.json" || fl_die "could not write $root/.finish/companions.json"
  summary "$root/.finish/companions.json"
}

summary() { # one line for logs
  jq -r '([.slots, .tools] | add | to_entries | map(select(.value)) | map("\(.key)=\(.value | tostring | split("/") | last)")) as $on
         | if .mode == "off" then "companions: off (FINISH_COMPANIONS=off)"
           elif ($on | length) == 0 then "companions: none installed (optional: scripts/companions.sh install)"
           else "companions: " + ($on | join(" ")) end' "$1"
}

show() { # <repo root>
  local f="$1/.finish/companions.json"
  [[ -f "$f" ]] || { echo "no $f — run: companions.sh detect"; return 1; }
  jq -r --slurpfile c "$CAT" '
    "Companions (\(.mode), detected \(.at)) — use each only at its step, by this exact name; empty = built-in step",
    (.slots | to_entries[] | "  \(.key | . + "         " | .[0:9]) \((.value // "—") | . + "                                              " | .[0:46]) \($c[0].slots[.key].step)"),
    (.tools | to_entries[] | "  \(.key | . + "         " | .[0:9]) \((.value // "—")) \($c[0].tools[.key].step)"),
    (if (.packs | length) > 0 then "  packs: " + ([.packs | to_entries[] | "\(.key) \(.value)"] | join(" · ")) else empty end)' "$f"
}

policy() { # [--runner]
  local runner=0 nohooks=false
  [[ "${1:-}" == --runner ]] && runner=1
  [[ $runner -eq 1 && "${FINISH_KEEP_HOOKS:-0}" != 1 ]] && nohooks=true
  jq -c --argjson runner "$runner" --argjson nohooks "$nohooks" '
    def forms($n): ["Skill(\($n))", "Skill(\($n) *)"];
    . as $c
    | [ $c.packs[] | . as $p | $p.deny[]
        | if $p.type == "plugin" then forms("\($p.plugin):\(.)")
          else forms("\($p.prefix // "")\(.)") + (if $runner == 1 then forms(.) else [] end) end ]
    | flatten | unique
    | {permissions: {deny: (. + $c.deny_bash)}, env: $c.env}
      + (if $nohooks then {disableAllHooks: true} else {} end)' "$CAT"
}

settings() { # <repo root> — merge the interactive policy into .claude/settings.local.json, if finish-line made it
  local f="$1/.claude/settings.local.json" pol merged h gd owned
  [[ -f "$f" ]] || return 0
  gd="$(cd "$1" && cd "$(git rev-parse --git-dir)" && pwd)" || return 1
  owned="$gd/finish-line.settings-owned"
  h="$(fl_sha < "$f")"
  # Only a file finish-line wrote and nobody changed since: a shipped template or one of its own merges.
  if ! grep -qxF "$h" "$SKILL/templates/claude-settings.local.history" 2>/dev/null && ! grep -qxF "$h" "$owned" 2>/dev/null; then
    jq -e '(.permissions.allow // []) | index("Skill")' "$f" >/dev/null 2>&1 \
      || echo "• .claude/settings.local.json is your own, so it was left alone; to use companion skills in interactive sessions, merge in: companions.sh policy"
    return 0
  fi
  pol="$(policy)" || return 1
  merged="$(jq --argjson p "$pol" '
    def addall($xs): reduce $xs[] as $x (.; if any(.[]; . == $x) then . else . + [$x] end);
    .permissions.allow = ((.permissions.allow // []) | addall(["Skill"]))
    | .permissions.deny = ((.permissions.deny // []) | addall($p.permissions.deny))
    | .env = ((.env // {}) + $p.env)' "$f")" || return 1
  [[ "$(jq -S . <<< "$merged")" == "$(jq -S . "$f")" ]] && return 0
  printf '%s\n' "$merged" > "$f"
  fl_sha < "$f" >> "$owned"
  echo "• updated .claude/settings.local.json: companion skills allowed, their asking/planning/publishing skills denied"
}

list() {
  jq -r --slurpfile m "$MKT/.claude-plugin/marketplace.json" '
    . as $c
    | "Packs (pinned in companions/; install: companions.sh install [pack…])",
      (.packs | to_entries[] | .key as $k | .value as $p
        | ([$m[0].plugins[] | select(.name == $p.plugin)][0].source) as $src
        | "  \($k | . + "                  " | .[0:18]) \($p.license | split(" ")[0]) · \(if $p.install == null then "not offered for install" elif $p.type == "plugin" then "\($src.repo)@\($src.ref) \($src.sha[0:12])" else "\($p.repo) \($p.version) \($p.sha[0:12])" end)\(if $p.default then " · default" else "" end) · fills: \([$c.slots | to_entries[] | select(any(.value.use[]; .pack == $k)) | .key] | if length == 0 then "nothing" else join(", ") end) · denies \($p.deny | length) skills"),
      "Slots (first installed candidate wins)",
      (.slots | to_entries[] | "  \(.key | . + "         " | .[0:9]) \([.value.use[] | "\(.pack):\(.skill)"] | join(" > "))")' "$CAT"
}

# ---- install ---------------------------------------------------------------

mkt_ready=0
ensure_marketplace() {
  local out
  [[ $mkt_ready -eq 1 ]] && return 0
  if ! out="$(claude plugin marketplace add "$MKT" --scope user --json 2>&1)"; then
    echo "⚠ could not add the $MKT_NAME marketplace: $(printf '%s' "$out" | tail -1)"; return 1
  fi
  claude plugin marketplace update "$MKT_NAME" --json >/dev/null 2>&1 || true   # new pins after a skill upgrade
  mkt_ready=1
}

install_plugin() { # <pack>
  local pack="$1" plugin want existing out verb
  command -v claude >/dev/null 2>&1 || { echo "⚠ $pack: the claude CLI is needed to install plugins"; return 1; }
  plugin="$(cat_get --arg p "$pack" '.packs[$p].plugin')"; want="$plugin@$MKT_NAME"
  load_plugins
  existing="$(jq -r --arg n "$plugin" '[.[] | select(.name == $n) | .id][0] // empty' <<< "$PLUGINS")"
  if [[ -n "$existing" && "$existing" != "$want" ]]; then
    echo "• $pack: already installed as $existing — keeping it (finish-line's pinned build is $want; uninstall the other to switch)"
    return 0
  fi
  ensure_marketplace || return 1
  if [[ "$existing" == "$want" ]]; then verb=update; else verb=install; fi
  if out="$(claude plugin "$verb" "$want" --scope user --json 2>&1)"; then
    echo "• $pack: $(printf '%s\n' "$out" | tail -1 | jq -r '.message // .outcome' 2>/dev/null || printf '%s' "$out" | tail -1)"
  else
    echo "⚠ $pack: claude plugin $verb $want failed: $(printf '%s' "$out" | tail -1)"; return 1
  fi
}

install_git() { # <pack> — skills-dir packs (gstack): fetch the pinned commit, run its setup
  local pack="$1" dir url sha have a args=()
  fl_need git
  dir="$SKILLS_DIR/$(cat_get --arg p "$pack" '.packs[$p].dir')"
  url="$(cat_get --arg p "$pack" '.packs[$p].git')"; sha="$(cat_get --arg p "$pack" '.packs[$p].sha')"
  if [[ -e "$dir" ]]; then
    have="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo unknown)"
    if [[ "$have" == "$sha" ]]; then echo "• $pack: already at the pinned commit ${sha:0:12}"
    else echo "• $pack: $dir exists at ${have:0:12}; keeping it (finish-line's pin is ${sha:0:12}: git -C $dir fetch --depth 1 origin $sha && git -C $dir checkout FETCH_HEAD && (cd $dir && ./setup))"; fi
    return 0
  fi
  command -v bun >/dev/null 2>&1 || { echo "⚠ $pack: its ./setup needs Bun (https://bun.sh); not installed"; return 1; }
  mkdir -p "$SKILLS_DIR"
  if ! { git init -q "$dir" && git -C "$dir" remote add origin "$url" \
         && git -C "$dir" fetch -q --depth 1 origin "$sha" && git -C "$dir" checkout -q FETCH_HEAD; }; then
    echo "⚠ $pack: could not fetch $url at $sha"; rm -rf "$dir"; return 1
  fi
  while IFS= read -r a; do args+=("$a"); done < <(cat_get --arg p "$pack" '.packs[$p].setup[]?')
  if (cd "$dir" && ./setup ${args[@]+"${args[@]}"}); then
    echo "• $pack: installed at ${sha:0:12} into $dir"
  else
    echo "⚠ $pack: ./setup failed in $dir"; return 1
  fi
}

install() { # [pack…]
  local p kind rc=0
  # shellcheck disable=SC2046  # pack names are single words
  [[ $# -gt 0 ]] || set -- $(cat_get '.packs | to_entries[] | select(.value.default) | .key')
  for p in "$@"; do
    kind="$(cat_get --arg p "$p" '.packs[$p] | if . == null then "unknown" elif .install == null then "none" elif .install == "git" then "git" else "plugin" end')"
    case "$kind" in
      unknown) echo "⚠ $p: not in the catalog (companions.sh list)"; rc=1 ;;
      none) echo "• $p: not offered for install — see references/companions.md for what to borrow instead" ;;
      git) install_git "$p" || rc=1 ;;
      plugin) install_plugin "$p" || rc=1 ;;
    esac
  done
  if git rev-parse --show-toplevel >/dev/null 2>&1 && [[ -d "$(git rev-parse --show-toplevel)/.finish" ]]; then
    detect "$(git rev-parse --show-toplevel)"
  fi
  return $rc
}

repo_arg() { # [repo] → repo root
  local d="${1:-$PWD}"
  (cd "$d" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || fl_die "not a git repository: $d"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  detect) detect "$(repo_arg "${1:-}")" ;;
  show) show "$(repo_arg "${1:-}")" ;;
  policy) policy "${1:-}" ;;
  settings) settings "$(repo_arg "${1:-}")" ;;
  install) install "$@" ;;
  list) list ;;
  -h|--help|help|"") usage ;;
  *) fl_die "unknown command: $cmd (detect · show · policy · settings · install · list)" ;;
esac
