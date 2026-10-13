#!/usr/bin/env bash
set -euo pipefail

# Google Chrome in this session: the same two wallet keys as Brave ("Chrome
# Keys/Chrome Safe Storage" through kwalletd6, the Secret Service item "Chrome
# Safe Storage"), so the same guard, scripts/launch-chromium.sh. The desktop
# id is com.google.Chrome; google-chrome.desktop is the same entry under its
# older name, and both run google-chrome-stable.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
exec "$project_dir/scripts/launch-chromium.sh" com.google.Chrome google-chrome-stable "$@"
