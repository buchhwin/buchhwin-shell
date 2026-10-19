#!/usr/bin/env bash
set -euo pipefail
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/hypr.sh
source "$here/lib/hypr.sh"
# shellcheck source=lib/xrdb.sh
source "$here/lib/xrdb.sh"
# shellcheck source=lib/nested-guard.sh
source "$here/lib/nested-guard.sh"

# Make a cursor theme the default for applications started later in this
# session (Hyprland children, systemd and D-Bus activated services).
#
# It writes the *host's* systemd user environment, its D-Bus activation
# environment and its X resource database, which the project's rules put out of
# reach of a nested test. The gate for that lived only in the caller
# (AppearanceService's `realSession`); a script that can change the host for the
# rest of a login guards itself, the way session-action.sh does - and by the
# nested session's files, not only by the flag the testing recipe never exports.
if nested_environment; then
  printf 'apply-cursor-env: skipped in a nested test session\n' >&2
  exit 0
fi
theme=${1:?theme}
size=${2:?size}
# The size the X resource gets. XWayland draws its own cursor from it, in real
# pixels when "Sharp X11 applications" is on - so on a screen at 1.5 the
# caller passes 36 here for a 24 everywhere else, and the pointer stays one
# size across the two worlds. Left out, it is the size.
x11size=${3:-$size}
# The compositor's dialect as the shell already knows it (HyprCompat:
# "lua" or "legacy"); anything else is asked of hyprctl, as before.
dialect=${4:-}
[[ $theme =~ ^[A-Za-z0-9_.-]+$ && $size =~ ^[0-9]+$ && $x11size =~ ^[0-9]+$ ]] || { printf 'invalid cursor theme or size\n' >&2; exit 2; }
case $dialect in
  lua | legacy) ;;
  *) if hypr_is_lua; then dialect=lua; else dialect=legacy; fi ;;
esac
# The compositor's environment every time: hyprland.lua names a cursor theme
# of its own, so a config reload - one of the reasons the shell runs this -
# puts that one back.
if [[ $dialect == lua ]]; then
  hyprctl eval "hl.env(\"XCURSOR_THEME\", \"$theme\")
hl.env(\"XCURSOR_SIZE\", \"$size\")" >/dev/null
else
  hyprctl --batch "keyword env XCURSOR_THEME,$theme ; keyword env XCURSOR_SIZE,$size" >/dev/null
fi

# Everything below outlives a config reload and is the same for every run of
# one Hyprland session with the same values, and the shell runs this at every
# start, every config reload and every X11 scale change: about twenty
# processes, two dconf writes and a settings change every GTK and Flatpak
# application hears, for nothing new. The last run's values are kept in the
# session's runtime directory, keyed by the compositor instance and the X
# display, and a run that matches them stops here.
stamp=""
if [[ -n ${XDG_RUNTIME_DIR:-} ]]; then
  stamp=$XDG_RUNTIME_DIR/buchhwin-shell/cursor-applied
fi
applied="${HYPRLAND_INSTANCE_SIGNATURE:-} ${DISPLAY:-} $theme $size $x11size"
if [[ -n $stamp && -r $stamp && $(<"$stamp") == "$applied" ]]; then
  exit 0
fi

# --systemd updates the systemd user environment as well; a separate
# `systemctl --user set-environment` did the same thing twice.
dbus-update-activation-environment --systemd "XCURSOR_THEME=$theme" "XCURSOR_SIZE=$size"

# XWayland and GTK apps do not read XCURSOR_THEME from the compositor: an
# XWayland client (Electron with --ozone-platform=x11, for example) draws its
# own cursor from the X resource, and GTK apps read their own setting. Both
# used to keep saying breeze_cursors while everything Wayland-native followed
# the shell, so an XWayland app showed a Breeze cursor next to the new one.
if [[ -n ${DISPLAY:-} ]] && command -v xrdb >/dev/null 2>&1; then
  xrdb_merge "Xcursor.theme: $theme" "Xcursor.size: $x11size"
fi

# Flatpak applications (GTK, Electron, Chromium) ask the Settings portal, and
# its gtk backend answers org.gnome.desktop.interface from dconf - which kept
# saying breeze_cursors while the session, the X resources and the GTK files
# named the new theme: Flatpak and Electron applications kept showing Breeze.
# The portal announces the change, so running applications follow too.
# Only a value that differs is written: every write is a dconf change the
# portal announces to every application.
if command -v gsettings >/dev/null 2>&1; then
  if [[ $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true) != "'$theme'" ]]; then
    gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null || true
  fi
  if [[ $(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || true) != "$size" ]]; then
    gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null || true
  fi
fi

# Rewrite only the two cursor keys and keep the rest of the file. One backup,
# `settings.ini.buchhwin-backup`, holds the first version this script changed
# (the rule scripts/app-scroll.py follows); a fresh timestamped copy per change
# only piled up files nobody would ever restore. The replacement is written
# beside the file, with the file's mode, and moved into place - and it is
# removed again should the script die before the move.
tmp=""
trap '[[ -n $tmp ]] && rm -f -- "$tmp"' EXIT
for version in 3 4; do
  ini="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-$version.0/settings.ini"
  [[ -f $ini ]] || continue
  grep -q "^gtk-cursor-theme-name=$theme\$" "$ini" && grep -q "^gtk-cursor-theme-size=$size\$" "$ini" && continue
  [[ -e "$ini.buchhwin-backup" ]] || cp -p -- "$ini" "$ini.buchhwin-backup"
  tmp=$(mktemp -- "$ini.XXXXXX")
  sed -e "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$theme/" \
      -e "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$size/" "$ini" >"$tmp"
  grep -q '^gtk-cursor-theme-name=' "$tmp" || printf 'gtk-cursor-theme-name=%s\n' "$theme" >>"$tmp"
  grep -q '^gtk-cursor-theme-size=' "$tmp" || printf 'gtk-cursor-theme-size=%s\n' "$size" >>"$tmp"
  chmod --reference="$ini" -- "$tmp"
  mv -- "$tmp" "$ini"
  tmp=""
done

# Written last, so a run that stopped half way is not taken for a done one.
if [[ -n $stamp ]] && mkdir -p -m 700 -- "${stamp%/*}" 2>/dev/null; then
  tmp=$(mktemp -- "$stamp.XXXXXX") || exit 0
  printf '%s\n' "$applied" >"$tmp" && mv -- "$tmp" "$stamp"
  tmp=""
fi
