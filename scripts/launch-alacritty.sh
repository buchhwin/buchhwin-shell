#!/usr/bin/env bash
set -euo pipefail

# Alacritty in this session: the account's own configuration - the file Plasma
# reads too - with the transparency of Settings > Terminal on top
# (terminal.opacity, the value kitty uses), so the window is translucent here,
# where Hyprland blurs what lies behind it, and stays as the file says under
# Plasma. Only window.opacity is overridden, plus transparent_background_colors:
# without it the opacity reaches the default background only, and anything
# that paints its cells black itself (cmatrix, Arch's build has no
# use_default_colors) stays an opaque block. The rest is the user's.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# `--unit NAME` first, as for launch-kitty.sh: the window runs as a transient
# user service of that name (scripts/launch-app.sh) - the terminals of
# Settings > Updates, through scripts/launch-terminal.sh.
unit_args=()
if [[ ${1:-} == --unit ]]; then
  unit_args=(--unit "${2:?launch-alacritty: --unit needs a name}")
  shift 2
fi
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
opacity=0.8
if command -v jq >/dev/null 2>&1 && [[ -r $settings ]]; then
  value=$(jq -r '.terminal.opacity // empty' "$settings" 2>/dev/null || true)
  # A number from 0 to 1, or the default: whatever else is in the file never
  # reaches Alacritty's command line.
  if [[ $value =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then opacity=$value; fi
fi
exec "$project_dir/scripts/launch-app.sh" "${unit_args[@]}" Alacritty alacritty -o "window.opacity=$opacity" \
  -o colors.transparent_background_colors=true "$@"
