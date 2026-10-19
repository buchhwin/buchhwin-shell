#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
# The session's own shell is never a nested test's to touch. The environment
# that makes this possible is the one docs/testing.md tells you to export - the
# nested WAYLAND_DISPLAY, signature and XDG dirs - and BUCHHWIN_SHELL_PATH, the
# only thing that otherwise keeps this script local, was missing from that
# recipe for a long time. Without this guard, running it from a development
# checkout inside a nested session stops the shell on the user's own screen.
# It is asked again below, of the shell this copy will really act on.
if [[ $(readlink -f "${BUCHHWIN_SHELL_PATH:-$installed_dir}") == "$(readlink -f "$installed_dir")" ]] \
   && nested_environment; then
  printf 'stop-shell: the environment points at a nested session; refusing to act on %s\n' "$installed_dir" >&2
  printf 'stop-shell: set BUCHHWIN_SHELL_PATH to say which shell you mean\n' >&2
  exit 1
fi
# Half of a nested session's environment is refused too, as in
# reload-shell.sh: a signature and a display of two different sessions do not
# say which shell is meant, and quickshell looks for it on the display alone.
if nested_mixed_environment; then
  printf 'stop-shell: HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY belong to different sessions; refusing\n' >&2
  printf 'stop-shell: for the nested session export every line scripts/nested-session.sh start prints\n' >&2
  exit 1
fi
# Called from another checkout (the development repository while the session
# runs from the stable worktree, see scripts/deploy.sh): act on the session's
# own copy instead of starting or stopping a shell from this checkout.
if [[ ${BUCHHWIN_SHELL_PATH:-$installed_dir} == "$installed_dir" && -x "$installed_dir/scripts/stop-shell.sh" \
      && $(readlink -f "$installed_dir") != "$(readlink -f "$project_dir")" ]]; then
  exec "$installed_dir/scripts/stop-shell.sh" "$@"
fi
if [[ -e "$installed_dir/shell.qml" && $(readlink -f "$installed_dir") == "$project_dir" ]]; then
  config_dir="$installed_dir"
else
  config_dir=${BUCHHWIN_SHELL_PATH:-$project_dir}
fi
# As in reload-shell.sh: the session's own copy acts on itself whatever
# BUCHHWIN_SHELL_PATH says, so the guard at the top is asked again of the
# shell that is really meant. Here it only keeps the two scripts alike - a
# stop finds shells by the caller's display, and the nested display has no
# installed shell to stop.
if [[ $(readlink -f "$config_dir") == "$(readlink -f "$installed_dir")" ]] && nested_environment; then
  printf 'stop-shell: the environment points at a nested session; refusing to act on %s\n' "$installed_dir" >&2
  printf 'stop-shell: run the stop from the checkout the nested session runs\n' >&2
  exit 1
fi
quickshell kill --path "$config_dir" 2>/dev/null || true
