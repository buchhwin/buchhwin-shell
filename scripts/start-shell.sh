#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
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
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
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

# One log per shell start; the previous one is kept as quickshell.log.old. A
# start that finds a running instance (--no-duplicate exits at once) keeps the
# log, because that instance still writes to it.
if ! quickshell list --path "$config_dir" --json 2>/dev/null | grep -q '"id"'; then
  [[ -e $log_file ]] && mv -f -- "$log_file" "$log_file.old"
fi

exec quickshell --no-duplicate --path "$config_dir" >>"$log_file" 2>&1
