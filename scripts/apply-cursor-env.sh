#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/hypr.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/hypr.sh"

# Make a cursor theme the default for applications started later in this
# session (Hyprland children, systemd and D-Bus activated services).
#
# It writes the *host's* systemd user environment, its D-Bus activation
# environment and its X resource database, which the project's rules put out of
# reach of a nested test. The gate for that lived only in the caller
# (AppearanceService's `realSession`); a script that can change the host for the
# rest of a login guards itself, the way session-action.sh does.
if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
  printf 'apply-cursor-env: skipped in a nested test session\n' >&2
  exit 0
fi
theme=${1:?theme}
size=${2:?size}
[[ $theme =~ ^[A-Za-z0-9_.-]+$ && $size =~ ^[0-9]+$ ]] || { printf 'invalid cursor theme or size\n' >&2; exit 2; }
if hypr_is_lua; then
  hyprctl eval "hl.env(\"XCURSOR_THEME\", \"$theme\")
hl.env(\"XCURSOR_SIZE\", \"$size\")" >/dev/null
else
  hyprctl --batch "keyword env XCURSOR_THEME,$theme ; keyword env XCURSOR_SIZE,$size" >/dev/null
fi
systemctl --user set-environment "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size"
dbus-update-activation-environment --systemd "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size"

# XWayland and GTK apps do not read XCURSOR_THEME from the compositor: an
# XWayland client (Electron with --ozone-platform=x11, for example) draws its
# own cursor from the X resource, and GTK apps read their own setting. Both
# used to keep saying breeze_cursors while everything Wayland-native followed
# the shell, so the ChatGPT app showed a Breeze cursor next to a macOS one.
if [[ -n ${DISPLAY:-} ]] && command -v xrdb >/dev/null 2>&1; then
  printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "$theme" "$size" | xrdb -merge - 2>/dev/null || true
fi

# Rewrite only the two cursor keys, keep the rest of the file, back it up once
# per change like the installers do.
for version in 3 4; do
  ini="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-$version.0/settings.ini"
  [[ -f $ini ]] || continue
  grep -q "^gtk-cursor-theme-name=$theme\$" "$ini" && grep -q "^gtk-cursor-theme-size=$size\$" "$ini" && continue
  cp -- "$ini" "$ini.backup-$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  sed -e "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$theme/" \
      -e "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$size/" "$ini" >"$tmp"
  grep -q '^gtk-cursor-theme-name=' "$tmp" || printf 'gtk-cursor-theme-name=%s\n' "$theme" >>"$tmp"
  grep -q '^gtk-cursor-theme-size=' "$tmp" || printf 'gtk-cursor-theme-size=%s\n' "$size" >>"$tmp"
  mv -- "$tmp" "$ini"
done
