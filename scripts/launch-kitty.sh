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

export ZDOTDIR="$project_dir/zsh"
exec kitty "${configs[@]}" -o shell=zsh "$@"
