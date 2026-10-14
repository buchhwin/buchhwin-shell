#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
# `--reap [DIR]` only ends the helpers a dead shell of DIR left behind (see
# reap_helpers below) and starts nothing; the session launcher asks for it on
# the way out.
reap_only=0
if [[ ${1:-} == --reap ]]; then
  reap_only=1
  shift
fi
# The Hyprland config passes the exact path so IPC calls with the same --path
# reach this instance.
if [[ -n ${1:-} ]]; then
  config_dir=$1
elif [[ -e "$installed_dir/shell.qml" && $(readlink -f "$installed_dir") == "$project_dir" ]]; then
  config_dir="$installed_dir"
else
  config_dir=${BUCHHWIN_SHELL_PATH:-$project_dir}
fi
# The shell talks to Hyprland through HYPRLAND_INSTANCE_SIGNATURE, and it
# inherits that from whoever started it. Started from a terminal outside the
# session - which is what scripts/deploy.sh does - it would inherit nothing and
# come up blind: no monitors in Settings > Displays, no saved scaling applied,
# no window rules, no dispatches, and one warning in the log to say so. So the
# signature is resolved here when it is missing, and only when exactly one
# instance is running: a second one means a nested test session, and guessing
# between them is how a test reaches the real session.
if (( ! reap_only )) && [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
  if [[ $(hyprctl instances 2>/dev/null | grep -c '^instance ') == 1 ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
  else
    printf 'start-shell: no single Hyprland instance; the shell starts without one\n' >&2
  fi
fi

state_dir=${XDG_STATE_HOME:-"$HOME/.local/state"}/buchhwin-shell
log_file="$state_dir/quickshell.log"
mkdir -p -- "$state_dir"

# Is an instance of this configuration listed? The answer is captured and then
# searched, never piped into `grep -q`: grep quits at its first match, the
# writer is left with SIGPIPE, and under pipefail that read as "no instance" -
# the restart below then stopped waiting for the dead instance to go, and the
# shell it started exited at once against it. The same mistake fc-list made in
# bootstrap.sh (docs/testing.md, Pitfalls).
instance_running() {
  local list
  list=$(quickshell list --path "$config_dir" --json 2>/dev/null) || return 1
  [[ $list == *'"id"'* ]]
}
note() { printf '%s start-shell: %s\n' "$(date -Is)" "$1" >>"$log_file"; }

# ---- the helpers a dead shell leaves behind ---------------------------------
# Quickshell's `Process` children are ordinary child processes, and a shell
# that dies on a signal - a crash, or the abort on losing the compositor at
# logout - runs no destructor that would end them. `nmcli monitor`, `udevadm
# monitor`, the lid inhibitor, cliphist's two wl-paste watchers, drives.py and
# the bluetooth agent then live on under PID 1: three of them from the
# previous login were still running on 2026-10-13, and a shell restarted after
# a crash starts a second set beside them (two wl-paste watchers storing into
# the same database). So they are ended before a replacement starts, and once
# more when the session ends (`--reap`, from the session launcher).
#
# Only this user's processes (`-u`), only whole command lines (anchored, the
# paths escaped), and never one whose parent is a living quickshell: a nested
# test session runs beside the real one with helpers that look the same, and
# ending the real session's lid inhibitor or clipboard watcher from a test's
# restart would be exactly the kind of damage this is meant to prevent.
#
# pgrep -f takes a regular expression; the path is a literal, so every
# character that means something to an ERE is escaped first (reload-shell.sh
# does the same). Quickshell may hand its scripts the resolved path rather
# than the symlink it was started through, so both spellings are accepted.
# The executable itself is listed by name or by its resolved path, and the
# python scripts run through their interpreter (`python3 <script> …`).
escape_ere() { printf '%s' "$1" | sed 's,[][\.*^$+?(){}|\\],\\&,g'; }
config_pattern=$(escape_ere "$config_dir")
real_dir=$(readlink -f -- "$config_dir" 2>/dev/null || printf '%s' "$config_dir")
if [[ $real_dir != "$config_dir" ]]; then
  config_pattern="($config_pattern|$(escape_ere "$real_dir"))"
fi
helper_patterns=(
  "^(\\S+ )?${config_pattern}/scripts/drives\\.py monitor\$"
  "^(\\S+ )?${config_pattern}/scripts/bluetooth-agent\\.py\$"
  '^(\S*/)?wl-paste --type (text|image) --watch cliphist -db-path \S*/buchhwin-shell/cliphist\.db -max-items [0-9]+ store$'
  '^(\S*/)?nmcli monitor$'
  '^(\S*/)?udevadm monitor --udev --subsystem-match=backlight$'
  '^(\S*/)?systemd-inhibit --what=handle-lid-switch --who=buchhwin-shell .* sleep infinity$'
)
reap_helpers() {
  local uid pattern pid parent parents reaped=0
  uid=$(id -u)
  for pattern in "${helper_patterns[@]}"; do
    parents=
    for pid in $(pgrep -u "$uid" -f "$pattern" 2>/dev/null || true); do
      parent=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)
      [[ -n $parent ]] || continue
      [[ $(cat "/proc/$parent/comm" 2>/dev/null || true) == quickshell ]] && continue
      [[ ,$parents, == *,"$parent",* ]] || parents+=${parents:+,}$parent
      reaped=$(( reaped + 1 ))
    done
    [[ -n $parents ]] || continue
    # By parent rather than by pid: the parent was just checked, and the
    # pattern keeps it to the helpers.
    pkill -u "$uid" -P "$parents" -f "$pattern" 2>/dev/null || true
  done
  if (( reaped )); then note "ended $reaped helper(s) left behind by a shell that is gone"; fi
}

if (( reap_only )); then
  # Called as the compositor ends, with the shell on its way out behind it
  # (losing the compositor is an abort, not an exit): wait for its instance
  # to go, up to 5 s, rather than end helpers it still owns, and leave them
  # alone if it never goes.
  for _ in {1..100}; do
    instance_running || break
    sleep 0.05
  done
  if instance_running; then
    note "asked to reap, but an instance of this configuration is still listed - leaving its helpers alone"
  else
    reap_helpers
  fi
  exit 0
fi

# Every other way out ends what the shell left behind too: a SIGTERM that the
# shell dies of, a status that is not a crash, the compositor gone (how every
# nested test session ends) and the restart limit. Only once the instance is
# no longer listed, as above; helpers now carry --pdeathsig (Paths.bound),
# this is the net for anything that does not.
trap 'instance_running || reap_helpers' EXIT

# One log per shell start; the previous one is kept as quickshell.log.old. A
# start that finds a running instance (--no-duplicate exits at once) keeps the
# log, because that instance still writes to it.
if ! instance_running; then
  [[ -e $log_file ]] && mv -f -- "$log_file" "$log_file.old"
fi

# ---- and it is watched while it runs ---------------------------------------
# The shell used to be `exec`ed and that was the end of this script's job, so a
# crash simply left the desktop without a shell until somebody noticed. It is
# not hypothetical: `coredumpctl` on 2026-09-22 listed **six** SIGSEGVs of
# quickshell in one day, all of them inside Qt's own HTTP/2 header parser
# (`QHttpHeaderParser::setStatusCode` under `QHttp2ProtocolHandler`, reached
# through OpenSSL) - not this project's QML, and nothing this project can fix.
# What it can do is come back.
#
# **Only a crash is restarted.** `stop-shell.sh` and `deploy.sh` end the shell
# with `quickshell kill`, which is a clean exit, and a SIGTERM is somebody
# asking it to go; either would otherwise race the caller by starting a second
# shell behind it. A process that died on a signal reports 128 + that signal,
# so the two cases are told apart exactly rather than guessed at.
#
# **And only five times a minute**, the same brake systemd would have applied:
# a shell that crashes on startup must not spin for ever. Past that it stops
# and says so, in the log the next person will read anyway.
#
# **And never into a session that is ending.** At logout and at shutdown
# systemd sends SIGTERM to everything in the session at once, and a shell
# that dies badly on the way out - Quickshell does, its IPC and reload paths
# both segfault - looked like a crash to be restarted: a fresh shell started
# against a compositor that was already gone, and blocked on its socket until
# systemd gave up on it 90 seconds later, with the user watching the spinner
# ("since yesterday I cannot restart any more"). So the SIGTERM this script
# receives is forwarded to the shell and ends the watching, and a restart is
# only ever attempted while the compositor's socket is still there.
restart_window=60
restart_limit=5
restarts=0
window_started=$SECONDS
stopping=0
child=

# Without a signature there is nothing to check against (a test, or a start
# outside any session), and the answer is the one this script always gave.
compositor_alive() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
  [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]
}
on_stop() {
  stopping=1
  [[ -n $child ]] && kill -TERM "$child" 2>/dev/null || true
}
trap on_stop TERM INT HUP

# The session exports QT_QPA_PLATFORMTHEME=kde for the applications; the shell
# itself runs without it (2026-10-13). The KDE platform theme plugin pulled
# KConfig, KIconThemes and KColorScheme into quickshell and watched kdeglobals
# for 35 MB of resident memory (377 → 343 MB in a nested session), and the
# shell used none of it: its fonts and colours are its own tokens, its dialogs
# are kdialog, and the one thing it did take from the plugin - the icon theme's
# name for Quickshell.iconPath - is handed over here through QS_ICON_THEME,
# read from kdeglobals like the plugin did, else chosen by the shell's own
# theme (the symbolic icons of a dark theme are light). Launcher screenshots
# with and without the plugin differ in 604 of 537 600 pixels.
icon_theme=""
kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
# Guarded and status-caught: under `set -e` with pipefail a missing file (a
# nested session's sandbox has none) would end this script here, before the
# shell ever started (pitfall 15).
if [[ -r $kdeglobals ]]; then
  icon_theme=$(sed -n '/^\[Icons\]/,/^\[/{s/^Theme=//p}' "$kdeglobals" 2>/dev/null | head -n1) || icon_theme=""
fi
if [[ -z $icon_theme ]]; then
  icon_theme=breeze-dark
  settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
  if command -v jq >/dev/null 2>&1 && [[ -s $settings ]] \
     && [[ $(jq -r '.appearance.theme // "dark"' "$settings" 2>/dev/null) == light ]]; then
    icon_theme=breeze
  fi
fi

# glibc gives every thread that allocates its own malloc arena (up to 8 per
# core). The shell runs ~150 threads - a render thread per mapped window and
# Mesa's workers per GL context - and on 2026-10-13 about 410 of its 770 MB
# sat in 94 such arenas, mostly fragmented free space. Two are plenty for a
# program whose work happens on the GUI thread. An exported value wins (A/B).
malloc_arenas=${MALLOC_ARENA_MAX:-2}

while true; do
  status=0
  env -u QT_QPA_PLATFORMTHEME QS_ICON_THEME="$icon_theme" MALLOC_ARENA_MAX="$malloc_arenas" \
    quickshell --no-duplicate --path "$config_dir" >>"$log_file" 2>&1 &
  child=$!
  # `wait` returns as soon as a trapped signal arrives, before the shell has
  # gone; wait again for its real status.
  wait "$child" || status=$?
  while kill -0 "$child" 2>/dev/null; do
    status=0
    wait "$child" || status=$?
  done
  child=
  if (( stopping )); then
    note "asked to stop; the shell ended with status $status"
    exit 0
  fi
  (( status >= 128 )) || exit "$status"
  signal=$(( status - 128 ))
  # SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE. Anything else that carries a
  # signal - SIGTERM above all - is a request, not a fault.
  case $signal in
    11|6|7|4|8) ;;
    *) exit "$status" ;;
  esac
  if ! compositor_alive; then
    note "the shell died on signal $signal, but the compositor is gone - not restarting it"
    exit "$status"
  fi

  if (( SECONDS - window_started > restart_window )); then
    restarts=0
    window_started=$SECONDS
  fi
  restarts=$(( restarts + 1 ))
  if (( restarts > restart_limit )); then
    note "the shell died on signal $signal and has now done so $restart_limit times in ${restart_window}s - not restarting it again"
    exit "$status"
  fi
  note "the shell died on signal $signal, restarting ($restarts of $restart_limit)"
  sleep 1
  # The dead shell's instance can outlive it for a moment (the same lag
  # reload-shell.sh waits out): a replacement started against it exits 0 at
  # once because of --no-duplicate, and that 0 is read above as a clean exit -
  # the crash is then logged as restarted and the desktop has no shell. Wait
  # (up to 10 s) until quickshell no longer lists the instance.
  for _ in {1..200}; do
    instance_running || break
    sleep 0.05
  done
  # Its helpers outlived it (reap_helpers above): ended now, before the
  # replacement starts its own, or two of each run side by side. Not while
  # the instance is still listed - then the helpers may still be its.
  if ! instance_running; then reap_helpers; fi
done
