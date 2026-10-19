# shellcheck shell=bash
# Refuse to act unless the environment points at a nested Hyprland started by
# scripts/nested-session.sh (same BUCHHWIN_NESTED_DIR). Tools that inject input
# source this file and call nested_guard first, so they can never click or type
# in the user's real session. Source this file.

# True when the caller's environment points at a nested session started by
# scripts/nested-session.sh. Quiet, and it asks nothing of hyprctl or jq: this
# is for scripts that must *refuse* to touch the real session, not for tools
# that must be certain they are driving the nested one (that is nested_guard).
#
# It is easy to be in this environment by accident. The testing recipe has you
# export what scripts/nested-session.sh start prints - the nested
# WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE, BUCHHWIN_NESTED=1, the XDG
# dirs and BUCHHWIN_SHELL_PATH - and an older recipe left the last one out:
# reload-shell.sh then fell back to the installed copy and restarted the shell
# on the user's own screen.
# Hyprland built into the home directory (openSUSE Leap) on PATH, as in the
# session. The directory by parameter expansion rather than dirname: this is
# sourced by every lock and screenshot, and the two dirname processes were
# most of what sourcing it cost. Every caller sources it by a path.
# shellcheck source=hyprland-prefix.sh
if [[ -r "${BASH_SOURCE[0]%/*}/hyprland-prefix.sh" ]]; then source "${BASH_SOURCE[0]%/*}/hyprland-prefix.sh"; fi
nested_environment() {
  local base=${BUCHHWIN_NESTED_DIR:-"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-nested"}
  local pid
  if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
    return 0
  fi
  # Files of a nested Hyprland that is gone (crashed, never stopped) are
  # stale: a later real session can get the same wayland-N, and then its
  # suspend, reboot and lock fallback were skipped as "nested".
  if [[ -r $base/hyprland.pid ]]; then
    pid=$(<"$base/hyprland.pid")
    # /proc rather than kill -0, which says "no" for a living process of
    # another user (EPERM).
    if [[ ! $pid =~ ^[0-9]+$ || ! -d /proc/$pid ]]; then
      return 1
    fi
  fi
  if [[ -r $base/wayland-display && -n ${WAYLAND_DISPLAY:-} ]] \
     && [[ ${WAYLAND_DISPLAY} == "$(<"$base/wayland-display")" ]]; then
    return 0
  fi
  if [[ -r $base/instance && -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] \
     && [[ ${HYPRLAND_INSTANCE_SIGNATURE} == "$(<"$base/instance")" ]]; then
    return 0
  fi
  return 1
}

# True when the environment is half a nested session's: the nested signature
# with another display, or the nested display with another signature.
# reload-shell.sh and stop-shell.sh refuse it. The testing recipe once
# exported the nested signature but not the nested WAYLAND_DISPLAY, and
# quickshell finds its instances by display: a reload meant for the nested
# development shell found none on the user's screen and started a second one
# there, talking to the nested Hyprland (16.10.). Stale files (their Hyprland
# gone) say nothing, as in nested_environment.
nested_mixed_environment() {
  local base=${BUCHHWIN_NESTED_DIR:-"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-nested"} pid
  local nested_signature=0 nested_display=0
  [[ -r $base/instance && -r $base/wayland-display ]] || return 1
  if [[ -r $base/hyprland.pid ]]; then
    pid=$(<"$base/hyprland.pid")
    [[ $pid =~ ^[0-9]+$ && -d /proc/$pid ]] || return 1
  fi
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && $HYPRLAND_INSTANCE_SIGNATURE == "$(<"$base/instance")" ]]; then
    nested_signature=1
  fi
  if [[ -n ${WAYLAND_DISPLAY:-} && $WAYLAND_DISPLAY == "$(<"$base/wayland-display")" ]]; then
    nested_display=1
  fi
  (( nested_signature != nested_display ))
}

# True when the caller's XDG config, state and cache dirs are the nested
# sandbox's. A shell started for the nested session with any others reads and
# writes the user's own settings and layout, and its start moves the live
# shell's log aside (testing.md, pitfall 121) - reload-shell.sh refuses it.
nested_sandbox_dirs() {
  local base=${BUCHHWIN_NESTED_DIR:-"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-nested"}
  [[ ${XDG_CONFIG_HOME:-} == "$base/config" && ${XDG_STATE_HOME:-} == "$base/state" \
     && ${XDG_CACHE_HOME:-} == "$base/cache" ]]
}

# Prints the signature of the Hyprland session a shell started from here
# would belong to, and fails when there is none: the caller's own signature
# when its compositor socket is there, else the one instance hyprctl lists,
# if it runs on the caller's display (or the caller has none). The same rule
# start-shell.sh applies before it starts anything; reload-shell.sh and the
# deploy's reload (scripts/lib/reload.sh) ask first, so a run from Plasma -
# no Hyprland at all, or a signature the user manager kept from the last
# Hyprland login - restarts nothing and says so. Two
# instances are a nested test session beside the real one: no guess.
#
# A signature whose socket is there is not enough on its own either: with a
# Hyprland still running on another VT, the user manager hands its live
# signature to a Plasma terminal, next to KWin's WAYLAND_DISPLAY. Hyprland's
# lock file names the display it runs (its pid, then its socket, what
# `hyprctl instances` reads); one that names another display is no session
# of this caller. No lock file, or no second line, says nothing.
hyprland_session() {
  local runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} signature=${HYPRLAND_INSTANCE_SIGNATURE:-} listed socket
  if [[ -z $signature ]]; then
    command -v hyprctl >/dev/null 2>&1 || return 1
    listed=$(hyprctl instances 2>/dev/null) || listed=""
    [[ $(grep -c '^instance ' <<<"$listed") == 1 ]] || return 1
    socket=$(sed -n 's/^[[:space:]]*wl socket: *//p' <<<"$listed" | head -n1) || socket=""
    [[ -z ${WAYLAND_DISPLAY:-} || -z $socket || $socket == "$WAYLAND_DISPLAY" ]] || return 1
    signature=$(sed -n 's/^instance \(.*\):$/\1/p' <<<"$listed" | head -n1) || signature=""
  fi
  [[ -n $signature && -S $runtime/hypr/$signature/.socket.sock ]] || return 1
  socket=$(sed -n 2p "$runtime/hypr/$signature/hyprland.lock" 2>/dev/null) || socket=""
  [[ -z ${WAYLAND_DISPLAY:-} || -z $socket || $socket == "$WAYLAND_DISPLAY" ]] || return 1
  printf '%s\n' "$signature"
}

nested_guard_fail() {
  printf 'nested-guard: %s; refusing (start scripts/nested-session.sh and export its values)\n' "$1" >&2
  return 1
}

# nested_guard [OUTPUT]  (default BUCHTEST)
nested_guard() {
  local base=${BUCHHWIN_NESTED_DIR:-"${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-nested"}
  local output=${1:-BUCHTEST} signature display pid environment
  [[ -r $base/instance && -r $base/wayland-display && -r $base/hyprland.pid ]] \
    || { nested_guard_fail "no nested session files in $base"; return 1; }
  signature=$(<"$base/instance") display=$(<"$base/wayland-display") pid=$(<"$base/hyprland.pid")
  [[ -n $signature && ${HYPRLAND_INSTANCE_SIGNATURE:-} == "$signature" ]] \
    || { nested_guard_fail "HYPRLAND_INSTANCE_SIGNATURE is not the nested one"; return 1; }
  [[ -n $display && ${WAYLAND_DISPLAY:-} == "$display" ]] \
    || { nested_guard_fail "WAYLAND_DISPLAY is not the nested one"; return 1; }
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
    || { nested_guard_fail "nested Hyprland (pid $pid) is not running"; return 1; }
  # The process must really be the nested compositor, not a reused pid.
  # Captured, then searched: `| grep -qx` quits at its match, tr gets SIGPIPE,
  # and under a caller's pipefail the nested compositor read as not nested.
  environment=$({ tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null) || environment=""
  grep -qx 'BUCHHWIN_NESTED=1' <<<"$environment" \
    || { nested_guard_fail "pid $pid is not a nested buchhwin Hyprland"; return 1; }
  hyprctl -j instances 2>/dev/null | jq -e --arg s "$signature" --arg d "$display" --argjson p "$pid" \
    'any(.[]; .instance == $s and .wl_socket == $d and .pid == $p)' >/dev/null \
    || { nested_guard_fail "hyprctl does not list the nested instance with pid $pid and socket $display"; return 1; }
  hyprctl -j monitors 2>/dev/null | jq -e --arg o "$output" 'any(.[]; .name == $o)' >/dev/null \
    || { nested_guard_fail "output $output is missing in the nested session"; return 1; }
}
