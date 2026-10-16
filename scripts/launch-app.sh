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
# without readlink too (the script's own path then).
app_env=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null) || app_env=${BASH_SOURCE[0]}
app_env="${app_env%/*}/lib/app-env.sh"
# shellcheck source=lib/app-env.sh
if [[ -r $app_env ]] && source "$app_env" && declare -F app_env_restore >/dev/null; then
  app_env_restore || true
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
if command -v systemd-run >/dev/null 2>&1 && systemctl --user show --property=Version >/dev/null 2>&1; then
  if [[ -n $unit ]]; then
    forward=()
    for name in WAYLAND_DISPLAY DISPLAY XAUTHORITY HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_STATE_HOME \
        XDG_CACHE_HOME XDG_DATA_HOME ZDOTDIR BUCHHWIN_SHELL_PATH BUCHHWIN_NESTED QT_QPA_PLATFORMTHEME \
        LANG LANGUAGE $(compgen -e LC_); do
      if [[ -n ${!name:-} ]]; then forward+=("--setenv=$name=${!name}"); fi
    done
    exec systemd-run --user --quiet --collect --slice=app.slice --unit="$unit" \
      --description="$id (buchhwin-shell)" "${forward[@]}" -- "$@"
  fi
  exec systemd-run --user --scope --quiet --slice=app.slice \
    --unit="app-buchhwin-$(systemd-escape -- "$id")-$$.scope" -- "$@"
fi
if [[ -n $unit ]]; then
  # No user manager to give it a unit: out of the caller's tree all the same.
  setsid -f "$@" </dev/null >/dev/null 2>&1
  exit 0
fi
exec "$@"
