#!/usr/bin/env bash
# Start an application in a systemd scope of its own, named after its desktop
# entry - the way Plasma (app-<id>@<uuid>.service) and GNOME (app-glib-<id>-
# <pid>.scope) start everything.
#
#   launch-app.sh <desktop-id> <command> [args...]
#
# Why: xdg-desktop-portal takes an application's *identity* from the unit it
# runs in (xdp-app-info-host.c parses app-[<launcher>-]<id>-<random>.scope and
# app-<id>@<random>.service; anything else is an application without a name),
# and the Secret portal keeps a key per identity. Brave started straight from
# the shell ran in the session's own scope and had no identity; started from a
# link in an editor it ran in the editor's scope and *was* the editor; in
# Plasma it is com.brave.Browser. Each of those got a key of its own, and every
# switch between Plasma and this session logged Brave out of everything.
# GLib 2.84 on Leap does not scope what it launches (`gio launch` left a probe
# in the caller's unit), so gtk-launch and xdg-open alone do not help.
#
# The launcher prefix "buchhwin" is dropped by the portal's parser; the id is
# escaped the way systemd wants it (brave-browser -> brave\x2dbrowser) and
# decoded again on the other side. Without systemd-run, or without a user
# manager to talk to, the command runs as it is.
#
#   launch-app.sh --unit NAME <desktop-id> <command> [args...]
#
# runs it as a transient user service called NAME instead, and returns once it
# has started. A scope keeps the application in the caller's process tree,
# and a shell that stops cleanly ends its children: the terminal that runs
# Settings > Updates' `pacman -Syu` went with every reload or deploy, and
# pacman with it, mid-transaction (16.10.). A service is the user manager's
# child, survives the caller and can be watched by its name. It starts with
# the user manager's environment - the session's, which session-init.sh
# imports - plus the display, the locale, the XDG directories and the zsh
# profile of the caller (the session's zsh for kitty), which the manager may
# not have or have otherwise.
set -euo pipefail
# The application gets the session's environment back, not the shell's own
# settings (scripts/lib/app-env.sh). Without the file it runs as it did, and
# without readlink too (the script's own path then). The path as it was
# called needs no readlink unless this file itself is a link (as in
# launch-default.sh): every application start comes through here.
app_env=${BASH_SOURCE[0]}
if [[ $app_env != /* || -L $app_env ]]; then
  app_env=$(readlink -f -- "$app_env" 2>/dev/null) || app_env=${BASH_SOURCE[0]}
fi
app_env="${app_env%/*}/lib/app-env.sh"
# shellcheck source=lib/app-env.sh
if [[ -r $app_env ]] && source "$app_env" && declare -F app_env_restore >/dev/null; then
  app_env_restore || true
fi
# While X11 is sharp: Steam's scale (scripts/apply-x11-dpi.sh writes it; only
# Steam reads the variable) and the pointer size X11 is told
# (scripts/apply-cursor-env.sh), which X11 applications read from
# XCURSOR_SIZE before anything else. Reads, not processes.
if [[ -n ${XDG_RUNTIME_DIR:-} && -r $XDG_RUNTIME_DIR/buchhwin-shell/steam-scale ]]; then
  read -r steam_scale <"$XDG_RUNTIME_DIR/buchhwin-shell/steam-scale" || steam_scale=""
  if [[ $steam_scale =~ ^[0-9]+(\.[0-9]+)?$ ]]; then export STEAM_FORCE_DESKTOPUI_SCALING=$steam_scale; fi
fi
if [[ -n ${XDG_RUNTIME_DIR:-} && -r $XDG_RUNTIME_DIR/buchhwin-shell/x11-cursor-size ]]; then
  read -r x11_cursor <"$XDG_RUNTIME_DIR/buchhwin-shell/x11-cursor-size" || x11_cursor=""
  if [[ $x11_cursor =~ ^[0-9]+$ ]]; then export XCURSOR_SIZE=$x11_cursor; fi
fi
unit=""
if [[ ${1:-} == --unit ]]; then
  unit=${2:?usage: launch-app.sh --unit NAME <desktop-id> <command> [args...]}
  shift 2
fi
id=${1:?usage: launch-app.sh [--unit NAME] <desktop-id> <command> [args...]}
shift
(( $# )) || { printf 'launch-app: nothing to run for %s\n' "$id" >&2; exit 2; }
id=${id%.desktop}

# On the path of every start, so without a process of its own (16.10.: the
# two questions below cost 18 ms of a terminal's 340 to its window).
#
# The user manager is there when its own socket is: systemd-run --user and
# systemctl --user talk to it at $XDG_RUNTIME_DIR/systemd/private, and there
# is nothing to start a unit with when it is missing (a container, a login
# without a user manager). Asking `systemctl --user show` took 12 ms.
manager_running() {
  [[ -n ${XDG_RUNTIME_DIR:-} && -S $XDG_RUNTIME_DIR/systemd/private ]]
}
# A unit name part the way systemd-escape writes it (6 ms as a process):
# letters, digits, ':' and '_' stay, a '.' stays unless it comes first, '/'
# becomes '-', and every other byte - '-' too - is \xNN.
unit_escape() {
  local LC_ALL=C text=$1 char code i
  escaped=""
  for (( i = 0; i < ${#text}; i++ )); do
    char=${text:i:1}
    if [[ $char == / ]]; then
      escaped+=-
    elif [[ $char == [A-Za-z0-9:_] || ( $char == . && i -gt 0 ) ]]; then
      escaped+=$char
    else
      printf -v code '%d' "'$char"
      printf -v char '\\x%02x' $(( code & 255 ))
      escaped+=$char
    fi
  done
}
# A unit name has at most 255 characters, and systemd-run refuses a longer
# one - the application would not start at all. An id that escapes past what
# is left beside the prefix and the pid (a long name of spaces and symbols,
# each four characters escaped: Citrix's subscribed apps are named like
# "XenApp 7.x.RDS-Desk $S101-255") is cut at the edge of an escape. Every
# backslash in an escaped name begins one (a backslash itself is \x5c).
unit_shorten() {
  local max=$1 tail
  (( ${#escaped} > max )) || return 0
  escaped=${escaped:0:max}
  tail=${escaped: -3}
  if [[ $tail == *\\* ]]; then
    tail=${tail%\\*}
    escaped=${escaped:0:max-3+${#tail}}
  fi
}

if command -v systemd-run >/dev/null 2>&1 && manager_running; then
  if [[ -n $unit ]]; then
    forward=()
    # A nested session's unit keeps the marks scripts/nested-session.sh stop
    # finds the sandbox's processes by (BUCHHWIN_NESTED_MODE is the
    # compositor's own); without them it would outlive the sandbox.
    for name in WAYLAND_DISPLAY DISPLAY XAUTHORITY HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_STATE_HOME \
        XDG_CACHE_HOME XDG_DATA_HOME ZDOTDIR BUCHHWIN_SHELL_PATH BUCHHWIN_NESTED BUCHHWIN_NESTED_MODE QT_QPA_PLATFORMTHEME \
        LANG LANGUAGE $(compgen -e LC_); do
      if [[ -n ${!name:-} ]]; then forward+=("--setenv=$name=${!name}"); fi
    done
    exec systemd-run --user --quiet --collect --slice=app.slice --unit="$unit" \
      --description="$id (buchhwin-shell)" "${forward[@]}" -- "$@"
  fi
  unit_escape "$id"
  # app-buchhwin- (13), -<pid> (8 at most: pid_max is 4194304) and .scope (6).
  unit_shorten $(( 255 - 13 - 8 - 6 ))
  exec systemd-run --user --scope --quiet --slice=app.slice \
    --unit="app-buchhwin-$escaped-$$.scope" -- "$@"
fi
if [[ -n $unit ]]; then
  # No user manager to give it a unit: out of the caller's tree all the same.
  setsid -f "$@" </dev/null >/dev/null 2>&1
  exit 0
fi
exec "$@"
