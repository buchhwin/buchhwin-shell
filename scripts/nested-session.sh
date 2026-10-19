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
# sandbox when its environment says BUCHHWIN_NESTED=1, names this sandbox's
# XDG_CONFIG_HOME and carries BUCHHWIN_NESTED_MODE. The first two are no
# longer enough on their own: the testing recipe exports them, and a
# terminal's children - a smoke run, an editor started from it - carry them
# too. BUCHHWIN_NESTED_MODE is set on the compositor alone and printed for
# nobody, so only what the compositor started (and start-shell.sh carries
# from it) has it.
#
# Three greps over every environ at once: a tr and two greps per process took
# 0.6 s for 350 processes, and a fresh start asks up to ten times.
sandbox_pids() {
  local files file pid
  # grep exits 2 for the environ files of other users it cannot read, and
  # pipefail passes that on: the list is kept whatever the status says.
  files=$(grep -lzx 'BUCHHWIN_NESTED=1' /proc/[0-9]*/environ 2>/dev/null \
            | xargs -r grep -lzxF "XDG_CONFIG_HOME=$base/config" 2>/dev/null \
            | xargs -r grep -lz '^BUCHHWIN_NESTED_MODE=' 2>/dev/null) || true
  for file in $files; do
    pid=${file#/proc/}; pid=${pid%/environ}
    [[ $pid =~ ^[0-9]+$ && -O $file ]] && printf '%s\n' "$pid"
  done
  return 0
}
# The instance directories Quickshell keeps in the runtime directory (tmpfs,
# so memory) for each of the given pids, by its by-pid link: a nested shell
# killed with its compositor never removes its own, and each one held 0.3-0.8
# MB until logout.
quickshell_dirs() {
  local pid target root=${XDG_RUNTIME_DIR:-}/quickshell
  [[ -n ${XDG_RUNTIME_DIR:-} ]] || return 0
  for pid in "$@"; do
    target=$(readlink -- "$root/by-pid/$pid" 2>/dev/null) || continue
    [[ $target == "$root/by-id/"* && ${target##*/} =~ ^[a-z0-9]+$ ]] && printf '%s %s\n' "$pid" "$target"
  done
  return 0
}
# Removes those of the dirs whose process is gone, and the links to them.
remove_quickshell_dirs() {
  local pid dir link root=${XDG_RUNTIME_DIR:-}/quickshell
  while read -r pid dir; do
    [[ -n $pid && ! -d /proc/$pid ]] || continue
    rm -rf -- "$dir"
    rm -f -- "$root/by-pid/$pid"
    for link in "$root"/by-shell/*/"${dir##*/}"; do
      if [[ -L $link ]]; then rm -f -- "$link"; fi
    done
  done <<<"$1"
  return 0
}
stop_nested() {
  local pid leftovers environment="" signature="" hypr_dir="" shells=""
  if [[ -r "$base/hyprland.pid" ]]; then
    pid=$(<"$base/hyprland.pid")
    # Captured, then searched, as in sandbox_pids: `| grep -qx` would leave tr
    # with SIGPIPE, and pipefail then reads the nested Hyprland as not nested.
    if [[ $pid =~ ^[0-9]+$ ]]; then
      environment=$({ tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null) || environment=""
    fi
    if [[ $pid =~ ^[0-9]+$ ]] && grep -qx 'BUCHHWIN_NESTED=1' <<<"$environment"; then
      # Its own directory under $XDG_RUNTIME_DIR/hypr stays behind as well
      # (its log and a socket). Only the one whose lock file names this very
      # compositor is ever touched.
      [[ -r $base/instance ]] && signature=$(<"$base/instance")
      if [[ $signature =~ ^[A-Za-z0-9_]+$ && -n ${XDG_RUNTIME_DIR:-} ]] \
         && [[ $(sed -n 1p "$XDG_RUNTIME_DIR/hypr/$signature/hyprland.lock" 2>/dev/null) == "$pid" ]]; then
        hypr_dir="$XDG_RUNTIME_DIR/hypr/$signature"
      fi
      # shellcheck disable=SC2046 # one pid per word
      shells=$(quickshell_dirs $(sandbox_pids))
      kill "$pid" 2>/dev/null || true
      for _ in {1..60}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.05; done
      # Gone, and so is its lock file: its log is kept in the sandbox, the
      # rest goes. rmdir leaves a directory that holds anything else.
      if [[ -n $hypr_dir && ! -d /proc/$pid && ! -e $hypr_dir/hyprland.lock ]]; then
        if [[ -f $hypr_dir/hyprland.log ]]; then cp -f -- "$hypr_dir/hyprland.log" "$base/hyprland-instance.log" 2>/dev/null || true; fi
        rm -f -- "$hypr_dir/hyprland.log" "$hypr_dir/.socket.sock" "$hypr_dir/.socket2.sock"
        rmdir -- "$hypr_dir" 2>/dev/null || true
      fi
    elif [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      printf 'nested-session: pid %s is not a nested Hyprland; not killed\n' "$pid" >&2
    fi
    rm -f -- "$base/hyprland.pid"
  fi
  leftovers=$(sandbox_pids | grep -vx "$$" || true)
  if [[ -n $leftovers ]]; then
    # shellcheck disable=SC2086 # one pid per word
    shells+=${shells:+$'\n'}$(quickshell_dirs $leftovers)
    # shellcheck disable=SC2086 # one pid per word
    kill $leftovers 2>/dev/null || true
  fi
  # The shells go with their compositor, or with the kill above, a moment
  # later; their directories once they have.
  if [[ -n $shells ]]; then
    for _ in {1..20}; do
      remove_quickshell_dirs "$shells"
      # shellcheck disable=SC2046 # one pid per word
      [[ -z $(quickshell_dirs $(cut -d' ' -f1 <<<"$shells")) ]] && break
      sleep 0.05
    done
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
    # stop_nested has just sent them TERM; a scan of /proc takes ~20 ms.
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
# BUCHTEST's place belongs in the configuration too, not only in the runtime
# rule further down: `hyprctl reload` forgets runtime rules, the headless
# output then took the catch-all's 0x0 on top of the nested window's, and the
# per-monitor workspace blocks swapped screens by connector name (pitfall
# 120). A rule for an output that does not exist yet is harmless, and a named
# rule wins over the catch-all. hypr/hyprland.lua's nested branch has the
# same one.
printf '\n# The headless test output below (scripts/nested-session.sh).\nmonitor = BUCHTEST, %s@60, 4000x0, %s\n' \
  "$resolution" "$scale" >> "$base/hypr/hyprland.conf"

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
# The rest of what a terminal needs to act on the nested session, all of it
# meant to be exported (docs/testing.md, "Nested session"): a shell reloaded
# from there is a nested one, on the sandbox's XDG dirs (pitfall 121) and of
# this checkout, and the guards find this sandbox when it is not the default.
# With BUCHHWIN_NESTED exported, a reload, stop or deploy of the installed
# shell is refused from that terminal. BUCHHWIN_NESTED_MODE is left out on
# purpose: it marks what the compositor started (sandbox_pids).
printf 'BUCHHWIN_NESTED=1\n'
printf 'BUCHHWIN_NESTED_DIR=%s\n' "$base"
printf 'XDG_CONFIG_HOME=%s\n' "$base/config"
printf 'XDG_STATE_HOME=%s\n' "$base/state"
printf 'XDG_CACHE_HOME=%s\n' "$base/cache"
printf 'BUCHHWIN_SHELL_PATH=%s\n' "$project_dir"
