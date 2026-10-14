#!/usr/bin/env bash
set -euo pipefail

# Brave in this session: Plasma's password store (--password-store=kwallet6),
# and only with the wallet open. The guard and the reasons are in
# scripts/launch-chromium.sh, shared with Chrome and Chromium; this wrapper
# fixes the desktop id and the command, because LauncherService.appOverrides
# and the Hyprland binds run a script without arguments.
# Brave's own packages (Fedora, openSUSE) install /usr/bin/brave-browser;
# Arch's brave-bin from the AUR installs /usr/bin/brave, with the same
# brave-browser.desktop.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
exe=brave-browser
if ! command -v brave-browser >/dev/null 2>&1 && command -v brave >/dev/null 2>&1; then exe=brave; fi
exec "$project_dir/scripts/launch-chromium.sh" com.brave.Browser "$exe" "$@"
