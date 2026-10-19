#!/usr/bin/env bash
set -euo pipefail

# Google Chrome in this session: the same two wallet keys as Brave ("Chrome
# Keys/Chrome Safe Storage" through kwalletd6, the Secret Service item "Chrome
# Safe Storage"), so the same guard, scripts/launch-chromium.sh. The desktop
# id is com.google.Chrome; google-chrome.desktop is the same entry under its
# older name, and both run google-chrome-stable.
# The path as it was called, resolved only when this file itself is a link
# (as in launch-default.sh): two processes and two subshells less per start.
self=${BASH_SOURCE[0]}
[[ $self == /* && ! -L $self ]] || self=$(readlink -f -- "$self")
project_dir=${self%/*/*}
exec "$project_dir/scripts/launch-chromium.sh" com.google.Chrome google-chrome-stable "$@"
