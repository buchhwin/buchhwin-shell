#!/usr/bin/env bash
set -euo pipefail

# Chromium in this session: the same two wallet keys as Brave ("Chromium
# Keys/Chromium Safe Storage" through kwalletd6, the Secret Service item
# "Chromium Safe Storage"), so the same guard, scripts/launch-chromium.sh.
# Leap's package installs chromium-browser.desktop, which runs
# /usr/bin/chromium-browser (/usr/bin/chromium is a link to it); there is no
# org.chromium.Chromium entry on this system.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
exec "$project_dir/scripts/launch-chromium.sh" chromium-browser chromium-browser "$@"
