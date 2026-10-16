#!/usr/bin/env bash
set -euo pipefail

# Alacritty in this session: the account's own configuration - the file Plasma
# reads too - with the transparency of Settings > Terminal on top
# (terminal.opacity, the value kitty uses), so the window is translucent here,
# where Hyprland blurs what lies behind it, and stays as the file says under
# Plasma. Only window.opacity is overridden, plus transparent_background_colors:
# without it the opacity reaches the default background only, and anything
# that paints its cells black itself (cmatrix, Arch's build has no
# use_default_colors) stays an opaque block. The rest is the user's.
#
# One process for every window (terminal.alacrittyDaemon, on unless it says
# false): the first window starts `alacritty --daemon` through
# scripts/launch-app.sh - a scope of its own and the session's environment,
# from the home directory and in a session of its own, so it outlives the
# caller - and every window, the first too, is `alacritty msg create-window`
# to it. A window that way took about 90 ms from the command to the window, a
# new process 190 (16.10., nested, round11/launch). The window keeps what a
# new process would have had: the caller's working directory, the title,
# --hold, the command after -e, the opacity as the settings say it now. All
# windows share the one process: should it end, they all close (switch it
# off for a process each, from the next window on). The socket is named
# after the display and the Hyprland instance, so a daemon from an earlier
# login never gets this one's windows. A new process, as before, whenever the
# daemon cannot take the window: --unit (the window must be that unit's
# own), an option only a new process knows (another config file, verbosity,
# an X11 embed), no runtime directory or display, or a daemon that did not
# answer - one that is still alive is never replaced (its windows would go
# with it), and one that never came up is not tried again in this login.
# One process for the path, not three: this is on the path of every terminal.
self=$(readlink -f -- "${BASH_SOURCE[0]}")
project_dir=${self%/*/*}
# `--unit NAME` first, as for launch-kitty.sh: the window runs as a transient
# user service of that name (scripts/launch-app.sh) - the terminals of
# Settings > Updates, through scripts/launch-terminal.sh.
unit_args=()
if [[ ${1:-} == --unit ]]; then
  unit_args=(--unit "${2:?launch-alacritty: --unit needs a name}")
  shift 2
fi
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
opacity=0.8
daemon=true
# Both answers from one jq, apart by a unit separator (a tab is blank to
# `read` and would swallow an empty field), as in launch-kitty.sh.
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  if answers=$(jq -r '"\(.terminal.opacity // "")\u001f\(.terminal.alacrittyDaemon | if . == null then "" else tostring end)"' \
      "$settings" 2>/dev/null); then
    value="" daemon_value=""
    IFS=$'\x1f' read -r value daemon_value <<<"$answers" || true
    # A number from 0 to 1, or the default: whatever else is in the file never
    # reaches Alacritty's command line.
    if [[ $value =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then opacity=$value; fi
    if [[ $daemon_value == false ]]; then daemon=false; fi
  fi
fi
options=(-o "window.opacity=$opacity" -o colors.transparent_background_colors=true)

plain() {
  exec "$project_dir/scripts/launch-app.sh" "${unit_args[@]}" Alacritty alacritty "${options[@]}" "$@"
}

# The window as `alacritty msg create-window` takes it, in `window`, or
# status 1 for anything only a new process understands. The daemon's working
# directory is its own, so the caller's goes along, absolute.
window_options() {
  local cwd="" given=false
  window=()
  while (( $# )); do
    case $1 in
      --hold) window+=("$1"); shift ;;
      -T | --title | --class | -o | --option)
        (( $# >= 2 )) || return 1
        window+=("$1" "$2"); shift 2 ;;
      --title=* | --class=* | --option=*) window+=("$1"); shift ;;
      --working-directory)
        (( $# >= 2 )) || return 1
        cwd=$2 given=true; shift 2 ;;
      --working-directory=*) cwd=${1#*=} given=true; shift ;;
      -e | --command) break ;;
      *) return 1 ;;
    esac
  done
  if ! $given; then cwd=$PWD; fi
  if [[ $cwd != /* ]]; then cwd=$PWD/$cwd; fi
  if [[ ! -d $cwd ]]; then
    # One named that is not there: a new process says so itself.
    $given && return 1
    cwd=${HOME:-/}
  fi
  window=(--working-directory "$cwd" "${options[@]}" "${window[@]}" "$@")
}

# The daemon's socket, in `socket`; status 1 without a runtime directory of
# the user's or a display. A unix socket's path has room for 107 bytes.
daemon_socket() {
  local display=${WAYLAND_DISPLAY:-${DISPLAY:-}} instance=${HYPRLAND_INSTANCE_SIGNATURE:-}
  [[ -n $display && -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -w $XDG_RUNTIME_DIR ]] || return 1
  # <commit>_<start time>_<random>: the last two tell the logins apart.
  instance=${instance#*_}
  socket="$XDG_RUNTIME_DIR/buchhwin-alacritty-${display//\//-}${instance:+-$instance}.sock"
  (( ${#socket} < 100 ))
}

open_window() {
  alacritty msg --socket "$socket" create-window "${window[@]}" </dev/null >/dev/null 2>&1
}

# A process that runs: not gone, and not a zombie its new parent has not
# reaped yet (the daemon is nobody's child once this script has ended).
running() {
  local stat=""
  [[ $1 =~ ^[0-9]+$ ]] && read -r stat 2>/dev/null < "/proc/$1/stat" || return 1
  stat=${stat##*") "}
  [[ ${stat%% *} != [ZX] ]]
}

# Alive by its pid, as written when it came up.
daemon_alive() {
  local pid=""
  [[ -r $state.pid ]] && read -r pid 2>/dev/null < "$state.pid" || return 1
  running "$pid"
}

# Up to 3 s for its socket. The lock's descriptor stays here: the daemon
# would otherwise hold it for as long as it runs.
start_daemon() {
  local pid i
  rm -f -- "$socket" "$state.pid"
  (
    cd -- "${HOME:-/}" || cd /
    exec setsid "$project_dir/scripts/launch-app.sh" Alacritty alacritty --daemon --socket "$socket" "${options[@]}" \
      </dev/null >/dev/null 2>&1 {lock_fd}>&-
  ) &
  pid=$!
  for (( i = 0; i < 60; i++ )); do
    if [[ -S $socket ]]; then
      printf '%s\n' "$pid" > "$state.pid"
      return 0
    fi
    running "$pid" || return 1
    sleep 0.05
  done
  kill "$pid" 2>/dev/null || true
  return 1
}

if $daemon && (( ${#unit_args[@]} == 0 )) && window_options "$@" && daemon_socket; then
  if [[ -S $socket ]] && open_window; then exit 0; fi
  state=${socket%.sock}
  # One start at a time: two keys before the first daemon is up get one. A
  # file this cannot write (a full runtime directory) ends no start under
  # set -e: the window is a process of its own then.
  if { exec {lock_fd}>>"$state.lock"; } 2>/dev/null; then
    if command -v flock >/dev/null 2>&1; then flock -w 5 "$lock_fd" || true; fi
    if [[ -S $socket ]] && open_window; then exit 0; fi
    if ! daemon_alive && [[ ! -e $state.failed ]]; then
      if start_daemon; then
        if open_window; then exit 0; fi
        # Just started and no window: nothing of anyone's goes with it.
        daemon_pid=""
        read -r daemon_pid 2>/dev/null < "$state.pid" || true
        if [[ $daemon_pid =~ ^[0-9]+$ ]]; then kill "$daemon_pid" 2>/dev/null || true; fi
        rm -f -- "$socket" "$state.pid" 2>/dev/null || true
      fi
      : 2>/dev/null > "$state.failed" || true
    fi
    exec {lock_fd}>&-
  fi
fi
plain "$@"
