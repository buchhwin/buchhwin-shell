#!/usr/bin/env bash
set -euo pipefail

# Start an X11 application at 1x while X11 is told a larger scale.
#
# With Settings > Displays > "Sharp X11 applications" on, `Xft.dpi` carries
# the scale of the big screens, and every X11 window is sized for them. A
# window that lives on a screen at scale 1 - the Citrix Workspace window on
# the Full HD screen beside two 4K ones - is then too large by that scale.
# This undoes it for one GTK application: it reads the DPI X11 is being told
# right now and hands the application the reciprocal as GDK_DPI_SCALE, so the
# window is 1x whatever the scale setting says, today and after it changes.
#
#   launch-x11-unscaled.sh COMMAND [ARGS...]
#
# GDK_BACKEND=x11 comes with it: a GTK application that could speak Wayland
# would not be an X11 window in the first place. Nothing else is touched; a
# Qt application would want QT_SCALE_FACTOR the same way.
(( $# )) || { printf 'Usage: %s COMMAND [ARGS...]\n' "$0" >&2; exit 2; }
scale=1
if [[ -n ${DISPLAY:-} ]] && command -v xrdb >/dev/null 2>&1; then
  dpi=$(xrdb -query 2>/dev/null | awk '/^Xft\.dpi:/ { print $2; exit }' || true)
  if [[ $dpi =~ ^[0-9]+$ ]] && (( dpi > 0 )); then
    scale=$(awk -v d="$dpi" 'BEGIN { printf "%.3f", 96 / d }')
  fi
fi
export GDK_BACKEND=x11 GDK_DPI_SCALE=$scale
exec "$@"
