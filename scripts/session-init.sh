#!/usr/bin/env bash
set -uo pipefail

# Login session setup, started once by the Hyprland config:
#   session-init.sh SHELL_PATH
# Makes the compositor environment available to D-Bus/systemd activated KDE and
# desktop services, restarts the portal and then starts the shell
# (scripts/start-shell.sh SHELL_PATH), so Quickshell registers with a portal
# that already knows this session. Steps that fail are reported and skipped;
# the shell starts in any case. Nested test sessions never run this script
# (they start start-shell.sh directly).
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_path=${1:-}
shell_started=0

# Login timeline, so a slow start can be told apart afterwards
# (scripts/session-check.sh prints it). The previous login stays as .old.
startup_log="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/startup.log"
mkdir -p -- "$(dirname -- "$startup_log")" 2>/dev/null || true
[[ -e $startup_log ]] && mv -f -- "$startup_log" "$startup_log.old" 2>/dev/null
start_ms=$(( $(date +%s%N) / 1000000 ))
mark() {
  local now=$(( $(date +%s%N) / 1000000 ))
  printf '%s +%5sms %s\n' "$(date +%H:%M:%S)" "$(( now - start_ms ))" "$*" >> "$startup_log" 2>/dev/null || true
}
mark "session-init started (Hyprland pid ${HYPRLAND_INSTANCE_SIGNATURE:-unknown})"

start_shell() {
  (( shell_started )) && return 0
  shell_started=1
  [[ -n $shell_path ]] || return 0
  setsid -f "$project_dir/scripts/start-shell.sh" "$shell_path" </dev/null >/dev/null 2>&1
  mark "shell started"
}
trap 'start_shell; mark "session-init finished"' EXIT

step() {
  local label=$1
  shift
  "$@" || printf 'session-init: step failed (%s): %s\n' "$?" "$*" >&2
  mark "$label"
}

if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
  printf 'session-init: nested session, only starting the shell\n' >&2
  exit 0
fi

# Cursor theme from the shell settings, before the environment is exported.
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
# A broken settings file must not stop the session setup below - and "broken"
# includes *empty*, which is what a crash during an atomic write leaves behind.
# jq exits 0 on a zero-byte file and prints nothing, so the `||` never fired
# and two empty variables went into the systemd user environment and the D-Bus
# activation environment for the whole login. Truncated-but-nonempty JSON does
# hit the `||`; only the empty case slipped through, so the value is checked
# rather than the exit status.
XCURSOR_THEME=""
XCURSOR_SIZE=""
if command -v jq >/dev/null 2>&1 && [[ -s $settings ]]; then
  XCURSOR_THEME=$(jq -r '.appearance.cursorTheme // "breeze_cursors"' "$settings" 2>/dev/null) || XCURSOR_THEME=""
  XCURSOR_SIZE=$(jq -r '.appearance.cursorSize // 24' "$settings" 2>/dev/null) || XCURSOR_SIZE=""
fi
[[ -n $XCURSOR_THEME && $XCURSOR_THEME != null ]] || XCURSOR_THEME=breeze_cursors
[[ $XCURSOR_SIZE =~ ^[0-9]+$ ]] || XCURSOR_SIZE=24
export XCURSOR_THEME XCURSOR_SIZE
hyprctl setcursor "$XCURSOR_THEME" "$XCURSOR_SIZE" >/dev/null 2>&1 || true
# Marked on its own. The first two timelines put 1.1-2.2 s between "session-init
# started" and "environment imported", and that gap holds three things: jq,
# this hyprctl call - answered from Hyprland's main loop, which at this point
# is still modesetting the outputs - and the systemd import below. The user
# manager was idle through both logins (its startup had finished 2.3 s before
# session-init began), so the import is not the obvious suspect it looked like;
# this mark is what tells the three apart at the next login.
mark "cursor set"

session_variables=(
  DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION
  QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE
)
step "environment imported" systemctl --user import-environment "${session_variables[@]}"
step "D-Bus activation environment" dbus-update-activation-environment --systemd "${session_variables[@]}"

step "session target" systemctl --user start buchhwin-shell-session.target

# KWallet. pam_kwallet5 in /etc/pam.d/sddm already put the login password into
# /run/user/$UID/kwallet5.socket, but the thing that *collects* it is
# /usr/libexec/pam_kwallet_init, and Plasma starts that from
# plasma-kwallet-pam.service. The unit is `static` and only PartOf
# graphical-session.target, so nothing pulls it in outside a Plasma session.
# Started here, before the portal, because the Secret portal routes to the
# wallet. Skipped without the unit or the socket.
#
# What this unlocks is **ksecretd**, which owns `org.freedesktop.secrets`:
# pam-kwallet on this Fedora execs /usr/bin/ksecretd and nothing else. It does
# *not* unlock `kwalletd6`, which is a separate daemon with its own lock, woken
# by whoever asks for `org.kde.kwalletd6`. Anything that wants its secrets
# without a prompt has to ask the Secret Service - which is why
# scripts/launch-brave.sh passes `--password-store=gnome-libsecret` rather than
# `kwallet6`.
if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kwallet5.socket" ]] \
   && systemctl --user cat plasma-kwallet-pam.service >/dev/null 2>&1; then
  step "kwallet unlocked" systemctl --user start plasma-kwallet-pam.service
fi
# The shell starts before the portal work: it only needs the environment above,
# and waiting for portal units (which can take a long time on a cold boot) used
# to leave the screen black until they were done.
start_shell
step "portal (Hyprland)" timeout 20 systemctl --user start xdg-desktop-portal-hyprland.service
# A portal left over from an earlier session (or activated before the
# environment import above) keeps its old desktop routing; restart it so Secret
# requests reach KWallet like in Plasma.
step "portal restarted" timeout 20 systemctl --user restart xdg-desktop-portal.service

# Standard XDG autostart (entries matching XDG_CURRENT_DESKTOP, e.g. KDE
# Connect, calendar reminders) unless turned off in Settings > Autostart.
if ! command -v jq >/dev/null 2>&1 || [[ ! -r $settings ]] || [[ $(jq -r '.autostart.system' "$settings" 2>/dev/null || echo true) != false ]]; then
  # Entries that are useless here (scripts/lib/autostart-skip.sh) are masked for
  # this user manager run only; the session launcher unmasks them at logout.
  # shellcheck source=lib/autostart-skip.sh
  source "$project_dir/scripts/lib/autostart-skip.sh"
  mapfile -t skipped_units < <(autostart_skip_units)
  if (( ${#skipped_units[@]} )); then
    step "autostart entries masked" systemctl --user mask --runtime "${skipped_units[@]}"
    systemctl --user stop "${skipped_units[@]}" 2>/dev/null || true
  fi
  # xdg-desktop-autostart.target refuses manual starts; this target wants it.
  step "XDG autostart" systemctl --user start buchhwin-shell-autostart.target
fi
step "polkit agent" systemctl --user start plasma-polkit-agent.service

# A previous desktop setup installs this generic Hyprland service globally via
# graphical-session.target. It owns the old dwl-style bar. Stop it only for this
# session; never disable or delete the user's legacy unit.
systemctl --user stop buchhwin-shell.service 2>/dev/null || true
