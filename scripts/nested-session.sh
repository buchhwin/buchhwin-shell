#!/usr/bin/env bash
set -euo pipefail

# Start a disposable nested Hyprland with this repository's shell for visual
# and IPC tests from another Wayland session. It never runs session-init.sh (the
# shell starts through start-shell.sh directly) and uses sandboxed XDG
# config/state/cache directories, so the real layout, settings and systemd user
# session stay untouched.
#
#   scripts/nested-session.sh start [WIDTHxHEIGHT] [SCALE]   prints env lines
#   scripts/nested-session.sh stop

project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
base=${BUCHHWIN_NESTED_DIR:-"${TMPDIR:-/tmp}/buchhwin-nested"}

stop_nested() {
  if [[ -r "$base/hyprland.pid" ]]; then
    kill "$(<"$base/hyprland.pid")" 2>/dev/null || true
    rm -f -- "$base/hyprland.pid"
  fi
  rm -f -- "$base/instance" "$base/wayland-display"
}

case "${1:-start}" in
  stop)
    stop_nested
    exit 0
    ;;
  start) ;;
  *)
    printf 'Usage: %s start [WIDTHxHEIGHT] [SCALE] | stop\n' "$0" >&2
    exit 2
    ;;
esac

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
  printf 'nested-session: a parent Wayland session is required\n' >&2
  exit 1
fi

resolution=${2:-1920x1200}
scale=${3:-1}
stop_nested
mkdir -p -- "$base/config" "$base/state" "$base/cache" "$base/hypr"
# Never share the host's Akonadi configuration with the sandbox: an Akonadi
# client that cannot reach the server starts its own akonadi_control with the
# sandboxed data dirs, which registered duplicate default resources in the
# host's agentsrc and removed the real server's akonadiconnectionrc on exit.
# Nested sessions keep the calendar in its "sandbox" state; use the synthetic
# `calendar preview` data instead. Links left by older runs are removed.
if [[ -L "$base/config/akonadi" ]]; then
  rm -f -- "$base/config/akonadi"
fi

# Rebuild the session config from the repository without session-only steps.
for file in "$project_dir"/hypr/*.conf; do
  sed -e "s|^\$projectPath = .*|\$projectPath = $project_dir|" \
      -e 's|^exec-once = \$projectPath/scripts/session-init.sh|exec-once = $projectPath/scripts/start-shell.sh|' \
      -e "s|^monitor = .*|monitor = , $resolution, 0x0, $scale|" \
      "$file" > "$base/hypr/$(basename -- "$file")"
done

before=$(ls -1 "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null || true)
# BUCHHWIN_NESTED_LUA=1 runs hypr/hyprland.lua (the Hyprland 0.57+ format)
# directly; it reads the nested settings from the environment.
config_file="$base/hypr/hyprland.conf"
if [[ ${BUCHHWIN_NESTED_LUA:-0} == 1 ]]; then
  config_file="$project_dir/hypr/hyprland.lua"
fi
BUCHHWIN_NESTED=1 BUCHHWIN_NESTED_MODE="$resolution" BUCHHWIN_NESTED_SCALE="$scale" BUCHHWIN_SHELL_PATH="$project_dir" \
XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/state" XDG_CACHE_HOME="$base/cache" \
  Hyprland --config "$config_file" >"$base/hyprland.log" 2>&1 &
printf '%s\n' "$!" > "$base/hyprland.pid"

signature=""
for _ in {1..100}; do
  signature=$(comm -13 <(printf '%s\n' "$before" | sort) \
    <(ls -1 "${XDG_RUNTIME_DIR}/hypr" 2>/dev/null | sort) | tail -n1)
  [[ -n "$signature" && -S "${XDG_RUNTIME_DIR}/hypr/$signature/.socket.sock" ]] && break
  sleep 0.1
done
if [[ -z "$signature" ]]; then
  printf 'nested-session: Hyprland did not start; see %s\n' "$base/hyprland.log" >&2
  exit 1
fi

display=""
for _ in {1..50}; do
  display=$(HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl -j instances 2>/dev/null \
    | jq -r --arg s "$signature" '.[] | select(.instance == $s) | .wl_socket' 2>/dev/null || true)
  [[ -n "$display" ]] && break
  sleep 0.1
done

# A headless output renders independently of the parent window, so
# screenshots work even when the nested window is hidden. It also gives the
# shell a second monitor to lay out.
output=""
if HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl output create headless BUCHTEST >/dev/null 2>&1; then
  output=BUCHTEST
  if [[ ${BUCHHWIN_NESTED_LUA:-0} == 1 ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl eval "hl.monitor({ output = \"BUCHTEST\", mode = \"${resolution}@60\", position = \"4000x0\", scale = ${scale} })" >/dev/null
  else
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl keyword monitor "BUCHTEST,${resolution}@60,4000x0,${scale}" >/dev/null
  fi
  if [[ ${BUCHHWIN_NESTED_LUA:-0} == 1 ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl dispatch 'hl.dsp.focus({ monitor = "BUCHTEST" })' >/dev/null
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl dispatch 'hl.dsp.cursor.move({ x = 4960, y = 600 })' >/dev/null
  else
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl dispatch focusmonitor BUCHTEST >/dev/null
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl dispatch movecursor 4960 600 >/dev/null
  fi
fi

# Read by scripts/lib/nested-guard.sh to recognise this nested session.
printf '%s\n' "$signature" > "$base/instance"
printf '%s\n' "$display" > "$base/wayland-display"
printf 'HYPRLAND_INSTANCE_SIGNATURE=%s\n' "$signature"
printf 'NESTED_OUTPUT=%s\n' "$output"
printf 'NESTED_WAYLAND_DISPLAY=%s\n' "$display"
printf 'NESTED_DIR=%s\n' "$base"
