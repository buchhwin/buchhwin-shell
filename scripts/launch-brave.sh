#!/usr/bin/env bash
set -euo pipefail

# Brave in this session: Plasma's password store (--password-store=kwallet6),
# and only with the wallet open. The guard and the reasons are in
# scripts/launch-chromium.sh, shared with Chrome and Chromium; this wrapper
# fixes the desktop id and the command, because LauncherService.appOverrides
# and the Hyprland binds run a script without arguments.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
exec "$project_dir/scripts/launch-chromium.sh" com.brave.Browser brave-browser "$@"
