#!/usr/bin/env bash
set -euo pipefail

# scripts/restore-minimized.sh against a stand-in hyprctl: the minimized
# windows (special:buchhwin-minimized-N) go back to N, one without a number
# to the workspace in front, in the dialect the session speaks - one batch
# for the conf, one eval for Lua -, and nothing else is moved: not the
# session's hidden helpers, not a scratchpad, not a window on a workspace.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-restoretest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() {
  if eval "$1"; then :; else printf 'FAIL restore-minimized: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
mkdir -p "$bin"
cat > "$sandbox/clients.json" <<'EOF'
[
  { "address": "0xa1", "class": "code", "workspace": { "id": -97, "name": "special:buchhwin-minimized-3" } },
  { "address": "0xb2", "class": "foot", "workspace": { "id": -96, "name": "special:buchhwin-minimized" } },
  { "address": "0xc3", "class": "kitty", "workspace": { "id": 2, "name": "2" } },
  { "address": "0xd4", "class": "xwaylandvideobridge", "workspace": { "id": -99, "name": "special:buchhwin-hidden" } },
  { "address": "0xe5", "class": "x", "workspace": { "id": -98, "name": "special:scratch" } },
  { "address": "0xf6", "class": "y", "workspace": { "id": -95, "name": "special:buchhwin-minimized-12" } }
]
EOF
printf '[]\n' > "$sandbox/none.json"
# The stand-in: answers -j clients and -j activeworkspace from the files the
# case names, `eval 'return 1'` as a Lua configuration only when LUA=1, and
# writes every dispatch it is sent to the log.
cat > "$bin/hyprctl" <<EOF
#!/usr/bin/env bash
case "\$1 \${2:-}" in
  "-j clients") cat "\$CLIENTS" ;;
  "-j activeworkspace") if [[ -n \${FRONT:-} ]]; then printf '{"id": %s}\n' "\$FRONT"; else exit 1; fi ;;
  "eval return 1") if [[ \${LUA:-0} == 1 ]]; then echo ok; else echo "eval is only for the Lua config" >&2; exit 1; fi ;;
  "eval "*) printf 'eval %s\n' "\$2" >> "$calls" ;;
  "--batch "*) printf 'batch %s\n' "\$2" >> "$calls" ;;
  *) printf 'other %s\n' "\$*" >> "$calls" ;;
esac
EOF
chmod +x "$bin/hyprctl"
export PATH="$bin:$PATH"
if [[ $(command -v hyprctl) != "$bin/hyprctl" ]]; then
  printf 'restore-minimized test: the stand-in is not first in PATH, refusing to run\n' >&2
  exit 1
fi
run() { : > "$calls"; env -u HYPRLAND_INSTANCE_SIGNATURE "$@" bash "$project_dir/scripts/restore-minimized.sh"; }

out=$(run CLIENTS="$sandbox/clients.json" FRONT=4 LUA=0)
check '[[ $(cat "$calls") == "batch dispatch movetoworkspacesilent 3,address:0xa1 ; dispatch movetoworkspacesilent 4,address:0xb2 ; dispatch movetoworkspacesilent 12,address:0xf6" ]]' \
  "conf: one batch, each back to its workspace, the one without a number to the one in front (got: $(cat "$calls"))"
check '[[ $out == "3 minimized window(s) back" ]]' "conf: says how many ($out)"

out=$(run CLIENTS="$sandbox/clients.json" FRONT=4 LUA=1)
check '[[ $(grep -c "^eval " "$calls") == 1 ]]' "Lua: one eval"
check 'grep -q "hl.dispatch(hl.dsp.window.move({ workspace = 3, window = \"address:0xa1\", follow = false }))" "$calls"' "Lua: the window back to 3"
check 'grep -q "workspace = 4, window = \"address:0xb2\"" "$calls" && grep -q "workspace = 12, window = \"address:0xf6\"" "$calls"' "Lua: and the others"
check '! grep -q "0xc3\|0xd4\|0xe5" "$calls"' "Lua: nothing else is moved - not a window on a workspace, not the hidden helpers, not a scratchpad"

out=$(run CLIENTS="$sandbox/clients.json" LUA=0)
check 'grep -q "movetoworkspacesilent 1,address:0xb2" "$calls"' "no workspace in front known: the first"

out=$(run CLIENTS="$sandbox/none.json" FRONT=4 LUA=0)
check '[[ ! -s $calls && $out == "no minimized windows" ]]' "nothing minimized: nothing sent"

if (( failures )); then
  printf 'restore-minimized test: %d failure(s)\n' "$failures"
  exit 1
fi
printf 'restore-minimized test: ok\n'
