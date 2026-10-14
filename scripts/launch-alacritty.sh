#!/usr/bin/env bash
set -euo pipefail

# Alacritty in this session: the account's own configuration - the file Plasma
# reads too - with the transparency of Settings > Terminal on top
# (terminal.opacity, the value kitty uses), so the window is translucent here,
# where Hyprland blurs what lies behind it, and stays as the file says under
# Plasma. Only window.opacity is overridden; the rest is the user's.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
opacity=0.8
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  value=$(jq -r '.terminal.opacity // empty' "$settings" 2>/dev/null || true)
  # A number from 0 to 1, or the default: whatever else is in the file never
  # reaches Alacritty's command line.
  if [[ $value =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then opacity=$value; fi
fi
exec "$project_dir/scripts/launch-app.sh" Alacritty alacritty -o "window.opacity=$opacity" "$@"
