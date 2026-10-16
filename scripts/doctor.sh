#!/usr/bin/env bash
set -u

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=install/lib/distro.sh
. "$project_dir/install/lib/distro.sh"
distro=$(distro_detect 2>/dev/null) || distro=fedora
package_tool=dnf5
[[ $distro == opensuse-leap ]] && package_tool=zypper
# Arch: the update check is checkupdates (pacman-contrib), not pacman itself.
[[ $distro == arch ]] && package_tool=checkupdates
# shellcheck source=lib/hyprland-prefix.sh
if [[ -r "$project_dir/scripts/lib/hyprland-prefix.sh" ]]; then . "$project_dir/scripts/lib/hyprland-prefix.sh"; fi
status=0
# Brave is brave-browser from Brave's own packages, brave from Arch's AUR.
for command_name in Hyprland hyprctl quickshell setpriv kitty zsh brave-browser dolphin; do
  if [[ $command_name == brave-browser ]] && ! command -v brave-browser >/dev/null 2>&1 \
      && command -v brave >/dev/null 2>&1; then
    command_name=brave
  fi
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf 'missing  %s\n' "$command_name"
    status=1
  fi
done

printf '\nVersions\n'
Hyprland --version 2>/dev/null | sed -n '1p' || true
quickshell --version 2>/dev/null || true
kitty --version 2>/dev/null || true
zsh --version 2>/dev/null || true

printf '\nProtected user configuration\n'
for config_path in \
  "$HOME/.config/hypr" \
  "$HOME/.config/quickshell" \
  "$HOME/.config/kitty" \
  "$HOME/.config/fastfetch" \
  "$HOME/.zshrc"; do
  if [[ -e "$config_path" ]]; then
    printf 'present  %s\n' "$config_path"
  else
    printf 'absent   %s\n' "$config_path"
  fi
done

printf '\nShell backends\n'
for command_name in brightnessctl wpctl pw-metadata pw-record playerctl nmcli udevadm plocate jq swaylock curl gammastep "$package_tool" flatpak plasma-discover; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       %s\n' "$command_name"
  else
    printf 'missing  %s (some shell features stay unavailable)\n' "$command_name"
  fi
done
# Hyprland shows its dialogs (and a startup notice when missing) with these.
if command -v hyprland-dialog >/dev/null 2>&1; then
  printf 'ok       hyprland-guiutils\n'
else
  printf 'missing  hyprland-guiutils (Hyprland dialogs and startup notice; %s)\n' "$(distro_install_hint "$distro" hyprland-guiutils)"
fi
# A default app without a launcher of its own (Firefox, Konsole, foot,
# Nautilus … in Settings > Default apps) and an app shortcut start through
# gtk-launch (scripts/launch-default.sh); without it the key does nothing, and
# nothing says why. GTK 3 ships it, in gtk3-tools on openSUSE.
if command -v gtk-launch >/dev/null 2>&1; then
  printf 'ok       gtk-launch\n'
else
  gtk_package=gtk3
  [[ $distro == opensuse-leap ]] && gtk_package=gtk3-tools
  printf 'missing  gtk-launch (default apps without a launcher of their own and app shortcuts do nothing; %s)\n' \
    "$(distro_install_hint "$distro" "$gtk_package")"
fi
# /usr/lib64 on Fedora and openSUSE, /usr/lib on Arch (where lib64 is a link
# to it, but the real path reads better in a check).
qt6_dir=/usr/lib64/qt6
[[ -d $qt6_dir ]] || qt6_dir=/usr/lib/qt6
[[ $distro == arch ]] && qt6_dir=/usr/lib/qt6
# The QML modules services/CalendarService.qml imports. Without any one of
# them the service fails to load and takes the whole shell with it, so each
# is required: PimCalendars (kdepim-addons), the Plasma calendar
# (plasma-workspace), KItemModels and Akonadi (merkuro pulls it in; on Fedora
# akonadi-server ships it). The package for the hint differs per distribution.
package_for() {
  case $distro in
    arch) printf '%s' "$1" ;;
    opensuse-leap) printf '%s' "$3" ;;
    *) printf '%s' "$2" ;;
  esac
}
while IFS='|' read -r module label package; do
  if [[ -d $qt6_dir/qml/$module ]]; then
    printf 'ok       %s QML module (%s)\n' "$label" "${module//\//.}"
  else
    printf 'missing  %s QML module %s (the shell does not load without it; %s)\n' \
      "$label" "${module//\//.}" "$(distro_install_hint "$distro" "$package")"
    status=1
  fi
done <<MODULES
org/kde/plasma/PimCalendars|KDE PIM calendar|kdepim-addons
org/kde/plasma/workspace/calendar|Plasma calendar|$(package_for plasma-workspace plasma-workspace plasma6-workspace)
org/kde/kitemmodels|KItemModels|$(package_for kitemmodels kf6-kitemmodels kf6-kitemmodels)
org/kde/akonadi|Akonadi|$(package_for merkuro akonadi-server merkuro)
MODULES
# The events themselves come from a plugin of the same package; without it
# the dashboard's events stay empty, and nothing else breaks.
if [[ -r $qt6_dir/plugins/plasmacalendarplugins/pimevents.so ]]; then
  printf 'ok       KDE calendar plugin (pimevents)\n'
else
  printf 'missing  KDE calendar plugin pimevents (dashboard events stay empty; %s)\n' "$(distro_install_hint "$distro" kdepim-addons)"
fi
# The Python bindings only write events, and Leap and Arch do not package
# them - optional.
if python3 -c 'import AkonadiCore' >/dev/null 2>&1; then
  printf 'ok       Akonadi Python bindings (writing calendar events)\n'
elif [[ $distro == fedora ]]; then
  printf 'missing  Akonadi Python bindings (writing events unavailable; Fedora: python3-kf6-kcoreaddons python3-kf6-kcalendarcore)\n'
else
  printf 'missing  Akonadi Python bindings (not packaged for %s: events are shown, not written)\n' "$distro"
fi
# From the bus's list, not with `busctl status`, which starts the daemon it
# asks about. An activatable name counts: the shell's first call starts it.
power_profiles=$(busctl --system --auto-start=no --no-pager list 2>/dev/null) || power_profiles=""
if awk '$1 == "net.hadess.PowerProfiles" { found = 1 } END { exit !found }' <<<"$power_profiles"; then
  printf 'ok       power profiles D-Bus service\n'
else
  printf 'missing  power profiles D-Bus service (profile controls hidden)\n'
fi

printf '\nSession integration\n'
portal_conf="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/buchhwin-shell-portals.conf"
if [[ -r "$portal_conf" ]] && grep -q 'Secret=kwallet' "$portal_conf"; then
  printf 'ok       portal routing (KWallet secrets): %s\n' "$portal_conf"
else
  printf 'missing  portal routing: %s (run install/install.sh --apply)\n' "$portal_conf"
fi
# Fedora activates it through a D-Bus service file; openSUSE's kwalletd6
# registers the name itself and ships only the portal file.
if [[ -r /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service \
      || -r /usr/share/xdg-desktop-portal/portals/kwallet.portal ]]; then
  printf 'ok       KWallet secret portal backend\n'
else
  printf 'missing  KWallet secret portal backend (kf6-kwallet)\n'
fi

printf '\nSession terminal\n'
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
fastfetch_config="$config_home/buchhwin-shell/fastfetch.jsonc"
if command -v fastfetch >/dev/null 2>&1; then
  printf 'ok       fastfetch: %s\n' "$(command -v fastfetch)"
else
  printf 'missing  fastfetch (optional)\n'
fi
# Terminal extras that follow the shell accent (Settings > Terminal writes
# their configuration): both from Fedora's and Arch's repositories, only cava
# from Leap's. And xclip, which the clipboard bridge needs to read what an
# X11 program copied - in every distribution's list.
for extra in cmatrix cava xclip; do
  if command -v "$extra" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$extra" "$(command -v "$extra")"
  else
    printf 'missing  %s (optional; %s)\n' "$extra" "$(distro_install_hint "$distro" "$extra")"
  fi
done
if [[ -r "$project_dir/zsh/.zshrc" ]]; then
  printf 'ok       session zshrc: %s\n' "$project_dir/zsh/.zshrc"
else
  printf 'missing  session zshrc: %s\n' "$project_dir/zsh/.zshrc"
  status=1
fi
if [[ -r "$fastfetch_config" ]]; then
  printf 'present  %s\n' "$fastfetch_config"
  logo=$(jq -r '.logo.source? // empty' "$fastfetch_config" 2>/dev/null || true)
  if [[ -n "$logo" && -r "${logo/#\~/$HOME}" ]]; then
    printf 'present  Fastfetch logo image\n'
  elif [[ -n "$logo" ]]; then
    printf 'missing  Fastfetch logo image: %s\n' "$logo"
  fi
else
  printf 'absent   %s (run install/install.sh --apply to copy it)\n' "$fastfetch_config"
fi

# The launcher's file search (/report, /png) asks plocate's index for what is
# under $HOME. On btrfs, /home is usually a subvolume of its own (@home), and
# updatedb takes a subvolume mounted from the same device for a bind mount:
# with PRUNE_BIND_MOUNTS = "yes" (Arch's default) it never indexes it, and
# every search ends in "No files found" (16.10.: 0 entries under /home, 4636
# under /etc). A machine setting, said rather than changed. .snapshots joins
# PRUNENAMES at the same time, or updatedb walks every snapper snapshot.
if command -v plocate >/dev/null 2>&1; then
  # -c prints the count and exits 1 when it is 0.
  home_entries=$(plocate -c -- "$HOME/" 2>/dev/null) || true
  if [[ $home_entries == 0 ]]; then
    printf '\nLauncher file search\n'
    printf 'note     plocate has nothing under %s, so the launcher finds no files\n' "$HOME"
    updatedb_conf=/etc/updatedb.conf
    home_fs=$(findmnt -no FSTYPE --target "$HOME" 2>/dev/null) || home_fs=""
    if [[ -r $updatedb_conf ]] && grep -qE '^[[:space:]]*PRUNE_BIND_MOUNTS[[:space:]]*=[[:space:]]*"?(yes|1)"?' "$updatedb_conf" \
        && [[ $home_fs == btrfs ]]; then
      printf '         (%s is a btrfs subvolume, which updatedb skips as a bind mount):\n' "$HOME"
      printf "         sudo sed -i -e 's/^PRUNE_BIND_MOUNTS *= *.*/PRUNE_BIND_MOUNTS = \"no\"/' -e '/^PRUNENAMES/{/\\.snapshots/!s/\"\$/ .snapshots\"/}' %s\n" "$updatedb_conf"
      printf '         sudo systemctl start plocate-updatedb.service\n'
    else
      printf '         (the index may be new or empty): sudo systemctl start plocate-updatedb.service\n'
    fi
  fi
fi

# A machine setting, said rather than changed: with transparent huge pages
# `always` the kernel backs mostly empty heap ranges with 2 MB pages, and the
# shell holds about twice its memory (15.10.: 340 against 180 MB). `madvise`
# gives them to the programs that ask, the usual setting on a desktop.
thp=/sys/kernel/mm/transparent_hugepage/enabled
if [[ -r $thp ]] && grep -q '\[always\]' "$thp"; then
  printf '\nMemory\n'
  printf 'note     transparent huge pages are "always"; "madvise" halves the shell'"'"'s memory:\n'
  printf '         echo madvise | sudo tee %s\n' "$thp"
fi

exit "$status"
