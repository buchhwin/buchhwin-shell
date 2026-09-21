#!/usr/bin/env bash
set -euo pipefail

# Start the session's default application for a category (Settings > Default
# Apps): browser (Super+B), files (Super+E), terminal (Super+Enter). Brave and
# Kitty keep their session launchers (KWallet, Zsh profile).
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
category=${1:?usage: launch-default.sh browser|files|terminal}
shift

desktop_id=$(python3 "$project_dir/scripts/default-apps.py" get "$category" 2>/dev/null || true)
case $desktop_id in
  brave-browser.desktop | com.brave.Browser.desktop) exec "$project_dir/scripts/launch-brave.sh" "$@" ;;
  kitty.desktop) exec "$project_dir/scripts/launch-kitty.sh" "$@" ;;
  ?*) exec gtk-launch "${desktop_id%.desktop}" "$@" ;;
esac

case $category in
  browser) exec "$project_dir/scripts/launch-brave.sh" "$@" ;;
  files) exec dolphin "$@" ;;
  terminal) exec "$project_dir/scripts/launch-kitty.sh" "$@" ;;
esac
exit 1
