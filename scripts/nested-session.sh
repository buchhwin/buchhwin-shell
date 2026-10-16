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
# BUCHHWIN_NESTED_FRESH=1 starts from an empty sandbox (see below; the deploy
# does), BUCHHWIN_NESTED_LUA=1 with hypr/hyprland.lua.

project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/hyprland-prefix.sh
if [[ -r "$project_dir/scripts/lib/hyprland-prefix.sh" ]]; then source "$project_dir/scripts/lib/hyprland-prefix.sh"; fi
# In the runtime directory (this user's, mode 0700) rather than a fixed name
# in /tmp that anyone could create first and fill with symlinks.
base=${BUCHHWIN_NESTED_DIR:-"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-nested"}

# The only process this ever kills is a Hyprland that was started here: the pid
# in the file may have been reused by anything since it was written, and the
# nested compositor is the one process on the machine whose environment says
# BUCHHWIN_NESTED=1 (the same check scripts/lib/nested-guard.sh makes).
#
# Once it is gone, whatever of this sandbox is still running goes too: the
# nested shell dies of the lost compositor without running a destructor, and
# its helpers used to live on under PID 1 (13 pairs of `nmcli monitor` and
# `udevadm monitor` after one day of smoke runs). A process belongs to the
# sandbox when its environment says BUCHHWIN_NESTED=1 and names this
# sandbox's XDG_CONFIG_HOME; nothing of the real session carries both.
sandbox_pids() {
  local env_file pid environment
  for env_file in /proc/[0-9]*/environ; do
    pid=${env_file#/proc/}; pid=${pid%/environ}
    [[ -O $env_file ]] || continue
    # A process of this user can still refuse its environ (a set-id one).
    environment=$({ tr '\0' '\n' <"$env_file"; } 2>/dev/null) || continue
    if grep -qx 'BUCHHWIN_NESTED=1' <<<"$environment" \
       && grep -qxF "XDG_CONFIG_HOME=$base/config" <<<"$environment"; then
      printf '%s\n' "$pid"
    fi
  done
}
stop_nested() {
  local pid leftovers environment=""
  if [[ -r "$base/hyprland.pid" ]]; then
    pid=$(<"$base/hyprland.pid")
    # Captured, then searched, as in sandbox_pids: `| grep -qx` would leave tr
    # with SIGPIPE, and pipefail then reads the nested Hyprland as not nested.
    if [[ $pid =~ ^[0-9]+$ ]]; then
      environment=$({ tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null) || environment=""
    fi
    if [[ $pid =~ ^[0-9]+$ ]] && grep -qx 'BUCHHWIN_NESTED=1' <<<"$environment"; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..60}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
    elif [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      printf 'nested-session: pid %s is not a nested Hyprland; not killed\n' "$pid" >&2
    fi
    rm -f -- "$base/hyprland.pid"
  fi
  leftovers=$(sandbox_pids | grep -vx "$$" || true)
  if [[ -n $leftovers ]]; then
    # shellcheck disable=SC2086 # one pid per word
    kill $leftovers 2>/dev/null || true
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
runtime_dir=${XDG_RUNTIME_DIR:?nested-session: XDG_RUNTIME_DIR is not set}

resolution=${2:-1920x1200}
scale=${3:-1}
stop_nested
mkdir -p -m 700 -- "$base"
if [[ ! -O $base || -L $base ]]; then
  printf 'nested-session: %s is not a directory of this user; not using it\n' "$base" >&2
  exit 1
fi
# BUCHHWIN_NESTED_FRESH=1 starts from an empty sandbox: the config, state and
# cache of the last run are removed first. They outlive the session (pitfall
# 92) - a wallpaper path another profile left failed a good deploy, a bar mode
# a failed smoke run left switched carried into the next one - and a first
# start (a fresh layout, the migrations) is otherwise never what a run tests.
# Only a sandbox this script built before (its hypr/hyprland.conf and
# hyprland.log are there), and only once nothing of it runs any more; else
# it is kept, and said. settings.json is
# seeded with the welcome tour done: it opens by itself a few seconds after a
# first start, over whatever the test opened (pitfall 102: written before the
# start, never under a running shell).
if [[ ${BUCHHWIN_NESTED_FRESH:-0} == 1 ]]; then
  fresh=1
  if [[ -f $base/hypr/hyprland.conf && -f $base/hyprland.log ]]; then
    # stop_nested has just sent them TERM; a scan of /proc takes ~0.3 s.
    running=""
    for _ in {1..10}; do
      running=$(sandbox_pids | grep -vx "$$" || true)
      [[ -z $running ]] && break
      sleep 0.2
    done
    if [[ -n $running ]]; then
      printf 'nested-session: processes of %s still run (%s); keeping its state\n' "$base" "$(tr '\n' ' ' <<<"$running")" >&2
      fresh=0
    else
      rm -rf -- "$base/config" "$base/state" "$base/cache"
    fi
  fi
  if (( fresh )) && [[ ! -e $base/config/buchhwin-shell/settings.json ]]; then
    mkdir -p -- "$base/config/buchhwin-shell"
    printf '{ "configVersion": 1, "onboarding": { "completed": true } }\n' > "$base/config/buchhwin-shell/settings.json"
  fi
fi
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

# BUCHHWIN_NESTED_LUA=1 runs hypr/hyprland.lua (the Hyprland 0.57+ format)
# directly; it reads the nested settings from the environment.
config_file="$base/hypr/hyprland.conf"
if [[ ${BUCHHWIN_NESTED_LUA:-0} == 1 ]]; then
  config_file="$project_dir/hypr/hyprland.lua"
fi
BUCHHWIN_NESTED=1 BUCHHWIN_NESTED_MODE="$resolution" BUCHHWIN_NESTED_SCALE="$scale" BUCHHWIN_SHELL_PATH="$project_dir" \
XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/state" XDG_CACHE_HOME="$base/cache" \
  Hyprland --config "$config_file" >"$base/hyprland.log" 2>&1 &
hyprland_pid=$!
printf '%s\n' "$hyprland_pid" > "$base/hyprland.pid"

# The instance is the one `hyprctl instances` lists with this pid. It used to
# be the lexically last new directory under $XDG_RUNTIME_DIR/hypr, which is a
# guess as soon as anything else starts a Hyprland in the same second - and a
# wrong guess here means every later call goes to somebody else's compositor.
signature=""
for _ in {1..100}; do
  signature=$(hyprctl -j instances 2>/dev/null \
    | jq -r --argjson p "$hyprland_pid" '[.[] | select(.pid == $p) | .instance][0] // empty' 2>/dev/null || true)
  [[ -n "$signature" && -S "$runtime_dir/hypr/$signature/.socket.sock" ]] && break
  signature=""
  sleep 0.1
done
if [[ -z "$signature" ]]; then
  printf 'nested-session: Hyprland (pid %s) did not come up; see %s\n' "$hyprland_pid" "$base/hyprland.log" >&2
  stop_nested
  exit 1
fi

display=""
for _ in {1..50}; do
  display=$(HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl -j instances 2>/dev/null \
    | jq -r --arg s "$signature" '.[] | select(.instance == $s) | .wl_socket' 2>/dev/null || true)
  [[ -n "$display" ]] && break
  sleep 0.1
done
# An empty wayland-display file is worse than no session: nested_guard reads
# it, and an empty display can never be the one a caller exported, so every
# tool refuses - while the compositor keeps running with nobody able to reach it.
if [[ -z "$display" ]]; then
  printf 'nested-session: instance %s reports no Wayland socket; stopping it; see %s\n' "$signature" "$base/hyprland.log" >&2
  stop_nested
  exit 1
fi

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
# The pair to export together: reload-shell.sh and stop-shell.sh refuse a
# nested signature with the session's display (or the other way round).
printf 'WAYLAND_DISPLAY=%s\n' "$display"
printf 'NESTED_DIR=%s\n' "$base"
