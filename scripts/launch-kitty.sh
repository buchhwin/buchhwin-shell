#!/usr/bin/env bash
set -euo pipefail

# Start Kitty with this session's appearance and a dedicated Zsh profile, so
# Fastfetch and history stay independent from other desktop sessions. The
# palette follows the shell theme (dark, light or automatic).
# One process for the path, not three: this is on the path of every terminal.
self=$(readlink -f -- "${BASH_SOURCE[0]}")
project_dir=${self%/*/*}
# `--unit NAME` first: the window runs as a transient user service of that
# name, outside the caller's process tree (scripts/launch-app.sh) - for the
# terminals of Settings > Updates (through scripts/launch-terminal.sh when
# kitty is the terminal), whose pacman must outlive a shell restart.
unit_args=()
if [[ ${1:-} == --unit ]]; then
  unit_args=(--unit "${2:?launch-kitty: --unit needs a name}")
  shift 2
fi
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
theme=dark
personal_shell=false
# Both answers from one jq (one process less on every kitty start), apart by
# a unit separator: a tab is blank to `read` and would swallow an empty field.
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  if answers=$(jq -r '"\(.appearance.theme // "dark")\u001f\(.terminal.personalShell // false)"' "$settings" 2>/dev/null); then
    IFS=$'\x1f' read -r theme personal_shell <<<"$answers" || true
  fi
  [[ -n $theme ]] || theme=dark
fi
if [[ $theme == auto ]]; then
  hour=$((10#$(date +%H)))
  theme=light
  (( hour >= 19 || hour < 7 )) && theme=dark
fi

configs=(--config "$project_dir/kitty/kitty.conf")
# Font, opacity, padding and cursor from Settings > Terminal.
overrides="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/kitty.conf"
[[ -r $overrides ]] && configs+=(--config "$overrides")
[[ $theme == light ]] && configs+=(--config "$project_dir/terminal/colors-light.conf")

# The session's own zsh configuration, unless Settings > Terminal says to use
# the account's ~/.zshrc (terminal.personalShell) - then zsh starts as it would
# anywhere else and the prompt settings are the account's business.
if [[ $personal_shell == true ]]; then
  unset ZDOTDIR
else
  export ZDOTDIR="$project_dir/zsh"
fi
# In a scope of its own, named after the entry (scripts/launch-app.sh).
exec "$project_dir/scripts/launch-app.sh" "${unit_args[@]}" kitty kitty "${configs[@]}" -o shell=zsh "$@"
