#!/usr/bin/env bash
set -euo pipefail

# Chromium in this session: the same two wallet keys as Brave ("Chromium
# Keys/Chromium Safe Storage" through kwalletd6, the Secret Service item
# "Chromium Safe Storage"), so the same guard, scripts/launch-chromium.sh.
# Leap's package installs chromium-browser.desktop, which runs
# /usr/bin/chromium-browser (/usr/bin/chromium is a link to it); there is no
# org.chromium.Chromium entry on this system. Arch's chromium installs
# /usr/bin/chromium and chromium.desktop, without the -browser name.
# The path as it was called, resolved only when this file itself is a link
# (as in launch-default.sh): two processes and two subshells less per start.
self=${BASH_SOURCE[0]}
[[ $self == /* && ! -L $self ]] || self=$(readlink -f -- "$self")
project_dir=${self%/*/*}
if ! command -v chromium-browser >/dev/null 2>&1 && command -v chromium >/dev/null 2>&1; then
  exec "$project_dir/scripts/launch-chromium.sh" chromium chromium "$@"
fi
exec "$project_dir/scripts/launch-chromium.sh" chromium-browser chromium-browser "$@"
