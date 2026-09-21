#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
# The session's own shell is never a nested test's to touch. The environment
# that makes this possible is the one docs/testing.md tells you to export - the
# nested WAYLAND_DISPLAY, signature and XDG dirs - while BUCHHWIN_SHELL_PATH,
# the only thing that otherwise keeps this script local, is not mentioned there
# at all. Without this guard, running it from a development checkout inside a
# nested session stops the shell on the user's own screen and, in the case of
# reload, starts a replacement pointed at the nested display.
if [[ $(readlink -f "${BUCHHWIN_SHELL_PATH:-$installed_dir}") == "$(readlink -f "$installed_dir")" ]] \
   && nested_environment; then
  printf 'stop-shell: the environment points at a nested session; refusing to act on %s\n' "$installed_dir" >&2
  printf 'stop-shell: set BUCHHWIN_SHELL_PATH to say which shell you mean\n' >&2
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
quickshell kill --path "$config_dir" 2>/dev/null || true
