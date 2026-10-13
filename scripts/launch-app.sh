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
# link in VS Code it ran in VS Code's scope and *was* VS Code; in Plasma it is
# com.brave.Browser. Each of those got a key of its own, and every switch
# between Plasma and this session logged Brave out of everything (2026-10-09).
# GLib 2.84 on Leap does not scope what it launches (`gio launch` left a probe
# in the caller's unit), so gtk-launch and xdg-open alone do not help.
#
# The launcher prefix "buchhwin" is dropped by the portal's parser; the id is
# escaped the way systemd wants it (brave-browser -> brave\x2dbrowser) and
# decoded again on the other side. Without systemd-run, or without a user
# manager to talk to, the command runs as it is.
set -euo pipefail
id=${1:?usage: launch-app.sh <desktop-id> <command> [args...]}
shift
(( $# )) || { printf 'launch-app: nothing to run for %s\n' "$id" >&2; exit 2; }
id=${id%.desktop}
if command -v systemd-run >/dev/null 2>&1 && systemctl --user show --property=Version >/dev/null 2>&1; then
  exec systemd-run --user --scope --quiet --slice=app.slice \
    --unit="app-buchhwin-$(systemd-escape -- "$id")-$$.scope" -- "$@"
fi
exec "$@"
