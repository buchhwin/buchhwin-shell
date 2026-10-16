#!/usr/bin/env bash
set -euo pipefail

# Start the session's default application for a category (Settings > Default
# Apps): browser (Super+B), files (Super+E), terminal (Super+Enter). The
# Chromium browsers (Brave, Chrome, Chromium), Kitty and Alacritty keep their
# session launchers (KWallet, Zsh profile, the terminal opacity), Dolphin
# starts by its program, anything else through gtk-launch. Without a
# default terminal, scripts/launch-terminal.sh decides, as it does for the
# shell's own terminals.
# One process for the path rather than three (readlink, dirname, a subshell):
# this is the start of every Super+Enter.
self=$(readlink -f -- "${BASH_SOURCE[0]}")
project_dir=${self%/*/*}
category=${1:?usage: launch-default.sh browser|files|terminal}
shift

# Looked up in bash (scripts/lib/default-terminal.sh, the same rule as
# default-apps.py, 20-85 ms faster): the terminal, and the browser and the
# file manager this session's own list names (Settings > Default apps).
# Anything it cannot answer for certain asks Python.
desktop_id=""
asked=false
if [[ -r $project_dir/scripts/lib/default-terminal.sh ]]; then
  # shellcheck source=lib/default-terminal.sh
  source "$project_dir/scripts/lib/default-terminal.sh"
  case $category in
    terminal) if desktop_id=$(default_terminal); then asked=true; fi ;;
    browser | files)
      mime=x-scheme-handler/http
      [[ $category == files ]] && mime=inode/directory
      if declare -F default_session_app >/dev/null && desktop_id=$(default_session_app "$mime"); then asked=true; fi ;;
  esac
fi
if ! $asked; then
  desktop_id=$(python3 "$project_dir/scripts/default-apps.py" get "$category" 2>/dev/null || true)
fi
case $desktop_id in
  brave-browser.desktop | com.brave.Browser.desktop) exec "$project_dir/scripts/launch-brave.sh" "$@" ;;
  google-chrome.desktop | com.google.Chrome.desktop) exec "$project_dir/scripts/launch-chrome.sh" "$@" ;;
  chromium-browser.desktop | chromium.desktop) exec "$project_dir/scripts/launch-chromium-browser.sh" "$@" ;;
  kitty.desktop) exec "$project_dir/scripts/launch-kitty.sh" "$@" ;;
  Alacritty.desktop) exec "$project_dir/scripts/launch-alacritty.sh" "$@" ;;
  # Dolphin by its program: gtk-launch would load GTK and connect to the
  # display only to start it.
  org.kde.dolphin.desktop) exec "$project_dir/scripts/launch-app.sh" org.kde.dolphin dolphin "$@" ;;
  ?*) exec "$project_dir/scripts/launch-app.sh" "$desktop_id" gtk-launch "${desktop_id%.desktop}" "$@" ;;
esac

case $category in
  browser) exec "$project_dir/scripts/launch-brave.sh" "$@" ;;
  files) exec "$project_dir/scripts/launch-app.sh" org.kde.dolphin dolphin "$@" ;;
  terminal) exec "$project_dir/scripts/launch-terminal.sh" "$@" ;;
esac
exit 1
