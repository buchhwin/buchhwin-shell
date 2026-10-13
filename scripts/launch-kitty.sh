#!/usr/bin/env bash
set -euo pipefail

# Start Kitty with this session's appearance and a dedicated Zsh profile, so
# Fastfetch and history stay independent from other desktop sessions. The
# palette follows the shell theme (dark, light or automatic).
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
theme=dark
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  theme=$(jq -r '.appearance.theme // "dark"' "$settings" 2>/dev/null || printf dark)
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
personal_shell=false
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  personal_shell=$(jq -r '.terminal.personalShell // false' "$settings" 2>/dev/null || printf false)
fi
if [[ $personal_shell == true ]]; then
  unset ZDOTDIR
else
  export ZDOTDIR="$project_dir/zsh"
fi
# In a scope of its own, named after the entry (scripts/launch-app.sh).
exec "$project_dir/scripts/launch-app.sh" kitty kitty "${configs[@]}" -o shell=zsh "$@"
