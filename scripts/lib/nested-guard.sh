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
# export the nested WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE and XDG dirs
# and says nothing about BUCHHWIN_SHELL_PATH - and reload-shell.sh then falls
# back to the installed copy and restarts the shell on the user's own screen.
nested_environment() {
  local base=${BUCHHWIN_NESTED_DIR:-"${TMPDIR:-/tmp}/buchhwin-nested"}
  if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
    return 0
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

nested_guard_fail() {
  printf 'nested-guard: %s; refusing (start scripts/nested-session.sh and export its values)\n' "$1" >&2
  return 1
}

# nested_guard [OUTPUT]  (default BUCHTEST)
nested_guard() {
  local base=${BUCHHWIN_NESTED_DIR:-"${TMPDIR:-/tmp}/buchhwin-nested"}
  local output=${1:-BUCHTEST} signature display pid
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
  tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qx 'BUCHHWIN_NESTED=1' \
    || { nested_guard_fail "pid $pid is not a nested buchhwin Hyprland"; return 1; }
  hyprctl -j instances 2>/dev/null | jq -e --arg s "$signature" --arg d "$display" --argjson p "$pid" \
    'any(.[]; .instance == $s and .wl_socket == $d and .pid == $p)' >/dev/null \
    || { nested_guard_fail "hyprctl does not list the nested instance with pid $pid and socket $display"; return 1; }
  hyprctl -j monitors 2>/dev/null | jq -e --arg o "$output" 'any(.[]; .name == $o)' >/dev/null \
    || { nested_guard_fail "output $output is missing in the nested session"; return 1; }
}
