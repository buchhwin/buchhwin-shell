#!/usr/bin/env bash
set -u

status=0
for command_name in Hyprland hyprctl quickshell kitty zsh brave-browser dolphin; do
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
for command_name in brightnessctl wpctl pw-metadata pw-record playerctl nmcli udevadm plocate jq swaylock curl gammastep dnf5 flatpak plasma-discover; do
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
  printf 'missing  hyprland-guiutils (Hyprland dialogs and startup notice; sudo dnf install hyprland-guiutils)\n'
fi
if [[ -r /usr/lib64/qt6/plugins/plasmacalendarplugins/pimevents.so && -d /usr/lib64/qt6/qml/org/kde/plasma/PimCalendars ]]; then
  printf 'ok       KDE calendar plugin (pimevents)\n'
else
  printf 'missing  KDE calendar plugin (kdepim-addons; dashboard events stay empty)\n'
fi
if python3 -c 'import AkonadiCore' >/dev/null 2>&1 && [[ -d /usr/lib64/qt6/qml/org/kde/akonadi ]]; then
  printf 'ok       Akonadi Python bindings and QML (calendar events)\n'
else
  printf 'missing  python3-kf6-kcoreaddons, python3-kf6-kcalendarcore or Akonadi QML (writing events unavailable)\n'
fi
if busctl --system status net.hadess.PowerProfiles >/dev/null 2>&1; then
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
if [[ -r /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service ]]; then
  printf 'ok       KWallet secret portal backend\n'
else
  printf 'missing  KWallet secret portal backend (kf6-kwallet)\n'
fi

printf '\nSession terminal\n'
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
fastfetch_config="$config_home/buchhwin-shell/fastfetch.jsonc"
if command -v fastfetch >/dev/null 2>&1; then
  printf 'ok       fastfetch: %s\n' "$(command -v fastfetch)"
else
  printf 'missing  fastfetch (optional)\n'
fi
# Terminal extras that follow the shell accent (Settings > Terminal writes
# their configuration): both come from Fedora's repositories.
for extra in cmatrix cava; do
  if command -v "$extra" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$extra" "$(command -v "$extra")"
  else
    printf 'missing  %s (optional; sudo dnf install %s)\n' "$extra" "$extra"
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

exit "$status"
