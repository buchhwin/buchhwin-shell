#!/usr/bin/env bash
set -u

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# --json: one JSON object per finding instead of the report, for Settings >
# About's Health (services/HealthService.qml) - {"level": "missing"|"note",
# "id", "text", "command"} for each miss and each note with a step, and
# {"kind": "result", "status"} last. What is there is not listed.
json=0
if [[ ${1:-} == --json ]]; then
  json=1
  exec 3>&1 1>/dev/null
fi
json_string() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\n'/\\n}
  text=${text//$'\r'/}
  text=${text//$'\t'/ }
  printf '"%s"' "$text"
}
# The step a miss's hint names, as a line to copy: a sudo command, an AUR
# helper's, or one of this checkout's installers (named relative in the text).
step_of() {
  local text=$1 step
  if [[ $text =~ (sudo [^\)\;]*[^\)\;[:space:]]) ]]; then
    # "sudo pacman -S bluez, then sudo systemctl enable --now bluetooth"
    step=${BASH_REMATCH[1]}
    printf '%s' "${step//, then / && }"
  elif [[ $text =~ (paru -S [^[:space:]\)]+) ]]; then printf '%s' "${BASH_REMATCH[1]}"
  elif [[ $text =~ (install/[a-z-]+\.sh --apply) ]]; then printf '%s/%s' "$project_dir" "${BASH_REMATCH[1]}"
  fi
}
finding() {
  (( json )) || return 0
  printf '{"level":%s,"id":%s,"text":%s,"command":%s}\n' "$(json_string "$1")" "$(json_string "$2")" \
    "$(json_string "$3")" "$(json_string "$4")" >&3
}
# shellcheck source=install/lib/distro.sh
. "$project_dir/install/lib/distro.sh"
# The family, not the installers' strict answer: an Arch derivative is Arch
# here (CachyOS was told to install dnf5, with Fedora's package names), and a
# system nobody knows gets no other system's commands - only package names.
distro=$(distro_family 2>/dev/null) || distro=""
package_tool=""
case $distro in
  fedora) package_tool=dnf5 ;;
  opensuse-leap) package_tool=zypper ;;
  # Arch: the update check is checkupdates (pacman-contrib), not pacman itself.
  arch) package_tool=checkupdates ;;
esac
# shellcheck source=lib/hyprland-prefix.sh
if [[ -r "$project_dir/scripts/lib/hyprland-prefix.sh" ]]; then . "$project_dir/scripts/lib/hyprland-prefix.sh"; fi
# /usr/lib64 on Fedora and openSUSE, /usr/lib on Arch (where lib64 is a link
# to it, but the real path reads better in a check). BUCHHWIN_QT6_DIR points
# at another tree (tests).
qt6_dir=/usr/lib64/qt6
[[ -d $qt6_dir ]] || qt6_dir=/usr/lib/qt6
[[ $distro == arch ]] && qt6_dir=/usr/lib/qt6
qt6_dir=${BUCHHWIN_QT6_DIR:-$qt6_dir}
status=0
# What fails the run: what the session cannot start without. Everything else
# that is missing is said and the run goes on - except with
# BUCHHWIN_DOCTOR_STRICT=1, for a machine the whole package list was
# installed on (CI), where any missing line fails it unless its id is in
# BUCHHWIN_DOCTOR_ALLOW (words, e.g. "brave-browser", which the AUR has).
strict=${BUCHHWIN_DOCTOR_STRICT:-0}
allowed=" ${BUCHHWIN_DOCTOR_ALLOW:-} "
# missing ID TEXT [required]
missing() {
  finding missing "$1" "$2" "$(step_of "$2")"
  printf 'missing  %s\n' "$2"
  if [[ ${3:-} == required ]] || [[ $strict == 1 && $allowed != *" $1 "* ]]; then status=1; fi
}
# The package a command comes in, where its name is not the command's; Arch's
# names (the closest to upstream's) for a system nobody knows.
package_of() {
  case ${distro:-arch}:$1 in
    *:wpctl) printf 'wireplumber' ;;
    arch:pw-metadata) printf 'pipewire' ;;
    arch:pw-record) printf 'pipewire-audio' ;;
    fedora:pw-metadata | fedora:pw-record) printf 'pipewire-utils' ;;
    opensuse-leap:pw-metadata | opensuse-leap:pw-record) printf 'pipewire-tools' ;;
    arch:nmcli) printf 'networkmanager' ;;
    *:nmcli) printf 'NetworkManager' ;;
    arch:udevadm) printf 'systemd' ;;
    fedora:udevadm) printf 'systemd-udev' ;;
    opensuse-leap:udevadm) printf 'udev' ;;
    *:checkupdates) printf 'pacman-contrib' ;;
    opensuse-leap:plasma-discover) printf 'discover6' ;;
    *) printf '%s' "$1" ;;
  esac
}
# The package per distribution: Arch's (and upstream's) name, Fedora's,
# openSUSE's.
package_for() {
  case $distro in
    fedora) printf '%s' "$2" ;;
    opensuse-leap) printf '%s' "$3" ;;
    *) printf '%s' "$1" ;;
  esac
}
for command_name in Hyprland hyprctl quickshell setpriv kitty zsh; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$command_name" "$(command -v "$command_name")"
  else
    missing "$command_name" "$command_name" required
  fi
done

# The browser and the file manager the keys start by default. A machine set
# up with --minimal or --skip-apps, or with Firefox and another file manager
# as its default apps, runs the session without them - said, not failed.
printf '\nApplications (optional)\n'
# Brave is brave-browser from Brave's own packages, brave from Arch's AUR.
for command_name in brave-browser dolphin; do
  if [[ $command_name == brave-browser ]] && ! command -v brave-browser >/dev/null 2>&1 \
      && command -v brave >/dev/null 2>&1; then
    command_name=brave
  fi
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$command_name" "$(command -v "$command_name")"
  else
    package=$command_name
    [[ $distro == arch && $command_name == brave-browser ]] && package=brave-bin
    missing "$command_name" "$command_name (optional; $(distro_install_hint "$distro" "$package"))"
  fi
done
# The assistant panel talks to a model Ollama runs on this computer, and to
# nothing else; without it the panel says how to get it. A note rather than
# a miss: no package list installs it, and most sessions never open it.
if command -v ollama >/dev/null 2>&1; then
  printf 'ok       ollama: %s\n' "$(command -v ollama)"
else
  ollama_hint=$(distro_install_hint "$distro" ollama)
  finding note ollama "ollama is not installed: the assistant panel needs it ($ollama_hint)" "$(step_of "$ollama_hint")"
  printf 'note     ollama is not installed: the assistant panel needs it (%s)\n' "$ollama_hint"
fi

printf '\nVersions\n'
Hyprland --version 2>/dev/null | sed -n '1p' || true
quickshell --version 2>/dev/null || true
# A note, not a miss: the shell is made on Quickshell 0.3, and Fedora's own
# 0.2.1 snapshot (which CI's Fedora job runs) still works with differences.
qs_line=$(quickshell --version 2>/dev/null) || qs_line=""
if [[ $qs_line =~ ([0-9]+)\.([0-9]+)\.[0-9]+ ]] && (( BASH_REMATCH[1] == 0 && BASH_REMATCH[2] < 3 )); then
  finding note quickshell-version "Quickshell ${BASH_REMATCH[0]} is older than 0.3.0, the version the shell is made on; expect differences" ""
  printf 'note     Quickshell %s is older than 0.3.0, the version the shell is made on; expect differences\n' "${BASH_REMATCH[0]}"
fi
# Which allocator quickshell links, and so which of start-shell.sh's two
# arena settings it reads. Read into a variable first (pitfall 15).
qs_path=$(command -v quickshell 2>/dev/null) || qs_path=""
if [[ -n $qs_path ]] && command -v readelf >/dev/null 2>&1; then
  qs_needed=$(readelf -d "$qs_path" 2>/dev/null) || qs_needed=""
  if [[ $qs_needed == *"NEEDED"*"libjemalloc"* ]]; then
    printf 'ok       quickshell allocates with jemalloc (start-shell.sh sets MALLOC_CONF)\n'
  elif [[ $qs_needed == *"NEEDED"* ]]; then
    printf 'ok       quickshell allocates with glibc malloc (start-shell.sh sets MALLOC_ARENA_MAX)\n'
  fi
fi
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
backends=(brightnessctl wpctl pw-metadata pw-record playerctl nmcli udevadm plocate jq swaylock curl gammastep)
[[ -n $package_tool ]] && backends+=("$package_tool")
backends+=(flatpak)
# Discover is the Updates page's way to upgrade, except on Arch, where the
# page runs the upgrade in a terminal (UpdatesLogic): not looked for there.
[[ $distro == arch ]] || backends+=(plasma-discover)
for command_name in "${backends[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       %s\n' "$command_name"
  else
    missing "$command_name" "$command_name (some shell features stay unavailable; $(distro_install_hint "$distro" "$(package_of "$command_name")"))"
  fi
done
# Hyprland shows its dialogs (and a startup notice when missing) with these.
if command -v hyprland-dialog >/dev/null 2>&1; then
  printf 'ok       hyprland-guiutils\n'
else
  missing hyprland-guiutils "hyprland-guiutils (Hyprland dialogs and startup notice; $(distro_install_hint "$distro" hyprland-guiutils))"
fi
# A default app without a launcher of its own (Firefox, Konsole, foot,
# Nautilus … in Settings > Default apps) and an app shortcut start through
# gtk-launch (scripts/launch-default.sh); without it the key does nothing, and
# nothing says why. GTK 3 ships it, in gtk3-tools on openSUSE.
if command -v gtk-launch >/dev/null 2>&1; then
  printf 'ok       gtk-launch\n'
else
  missing gtk-launch "gtk-launch (default apps without a launcher of their own and app shortcuts do nothing; $(distro_install_hint "$distro" "$(package_for gtk3 gtk3 gtk3-tools)"))"
fi
# The QML modules services/CalendarService.qml imports. Without any one of
# them the service fails to load and takes the whole shell with it, so each
# is required: PimCalendars (kdepim-addons), the Plasma calendar
# (plasma-workspace), KItemModels and Akonadi (merkuro pulls it in; on Fedora
# akonadi-server ships it). The package for the hint differs per distribution.
while IFS='|' read -r module label package; do
  if [[ -d $qt6_dir/qml/$module ]]; then
    printf 'ok       %s QML module (%s)\n' "$label" "${module//\//.}"
  else
    missing "qml:${module//\//.}" "$label QML module ${module//\//.} (the shell does not load without it; $(distro_install_hint "$distro" "$package"))" required
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
  missing calendar-plugin "KDE calendar plugin pimevents (dashboard events stay empty; $(distro_install_hint "$distro" kdepim-addons))"
fi
# The Python bindings only write events, and Leap and Arch do not package
# them - optional, and where nobody packages them nothing is missing.
if python3 -c 'import AkonadiCore' >/dev/null 2>&1; then
  printf 'ok       Akonadi Python bindings (writing calendar events)\n'
elif [[ $distro == fedora ]]; then
  missing akonadi-python "Akonadi Python bindings (writing events unavailable; $(distro_install_hint fedora "python3-kf6-kcoreaddons python3-kf6-kcalendarcore"))"
else
  printf 'note     Akonadi Python bindings are not packaged for %s: events are shown, not written\n' "${distro:-this system}"
fi
# From the bus's list, not with `busctl status`, which starts the daemon it
# asks about. A system bus that does not answer (a container) says nothing
# about the services on it.
system_bus=$(busctl --system --auto-start=no --no-pager list 2>/dev/null) || system_bus=""
if [[ -z $system_bus ]]; then
  printf 'skip     the system bus did not answer: power profiles, NetworkManager and BlueZ not checked\n'
else
  # An activatable name counts for the power profiles: the shell's first
  # call starts the daemon. Fedora's is tuned's.
  if awk '$1 == "net.hadess.PowerProfiles" { found = 1 } END { exit !found }' <<<"$system_bus"; then
    printf 'ok       power profiles D-Bus service\n'
  else
    missing power-profiles "power profiles D-Bus service (profile controls hidden; $(distro_install_hint "$distro" "$(package_for power-profiles-daemon tuned-ppd power-profiles-daemon)"))"
  fi
  # NetworkManager and BlueZ have to be running: nothing in the package
  # lists enables them, Arch enables no service a package brings, and the
  # network and Bluetooth panels then stay empty without a word.
  running_on_bus() { awk -v name="$1" '$1 == name && $2 ~ /^[0-9]+$/ { found = 1 } END { exit !found }' <<<"$system_bus"; }
  if running_on_bus org.freedesktop.NetworkManager; then
    printf 'ok       NetworkManager\n'
  else
    missing networkmanager "NetworkManager is not running (the network panels stay empty; sudo systemctl enable --now NetworkManager)"
  fi
  if running_on_bus org.bluez; then
    printf 'ok       BlueZ\n'
  else
    missing bluez "BlueZ is not running (no Bluetooth; $(distro_install_hint "$distro" bluez), then sudo systemctl enable --now bluetooth)"
  fi
fi

printf '\nSession integration\n'
portal_conf="${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/buchhwin-shell-portals.conf"
if [[ -r "$portal_conf" ]] && grep -q 'Secret=kwallet' "$portal_conf"; then
  printf 'ok       portal routing (KWallet secrets): %s\n' "$portal_conf"
else
  missing portal-routing "portal routing: $portal_conf (run install/install.sh --apply)"
fi
# Fedora activates it through a D-Bus service file; openSUSE's kwalletd6
# registers the name itself and ships only the portal file.
if [[ -r /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kwallet.service \
      || -r /usr/share/xdg-desktop-portal/portals/kwallet.portal ]]; then
  printf 'ok       KWallet secret portal backend\n'
else
  missing kwallet-portal "KWallet secret portal backend ($(distro_install_hint "$distro" "$(package_for kwallet kf6-kwallet kf6-kwallet)"))"
fi

printf '\nSession terminal\n'
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
fastfetch_config="$config_home/buchhwin-shell/fastfetch.jsonc"
if command -v fastfetch >/dev/null 2>&1; then
  printf 'ok       fastfetch: %s\n' "$(command -v fastfetch)"
else
  missing fastfetch "fastfetch (optional; $(distro_install_hint "$distro" fastfetch))"
fi
# Terminal extras that follow the shell accent (Settings > Terminal writes
# their configuration): both from Fedora's and Arch's repositories, only cava
# from Leap's. cava also draws the media popup's visualizer (Settings >
# Desktop extras > Media player). And xclip, which the clipboard bridge needs
# to read what an X11 program copied - in every distribution's list.
for extra in cmatrix cava xclip; do
  if command -v "$extra" >/dev/null 2>&1; then
    printf 'ok       %s: %s\n' "$extra" "$(command -v "$extra")"
  else
    missing "$extra" "$extra (optional; $(distro_install_hint "$distro" "$extra"))"
  fi
done
# The external monitors' brightness (Settings > Displays) needs ddcutil and
# its udev rule's access to the display buses: a note, not a miss - without it
# the monitors keep their own buttons.
if command -v ddcutil >/dev/null 2>&1; then
  printf 'ok       ddcutil: %s\n' "$(command -v ddcutil)"
else
  printf 'note     ddcutil is not installed, so external monitors have no brightness slider (%s)\n' "$(distro_install_hint "$distro" ddcutil)"
fi
# A timer's alarm (on by default) and the notification sounds (off by
# default) play the freedesktop theme through pw-play: a note, not a miss -
# without it they stay silent and nothing else changes.
if [[ ! -r /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga \
      || ! -r /usr/share/sounds/freedesktop/stereo/message-new-instant.oga ]]; then
  printf 'note     no freedesktop sound theme, so a timer'"'"'s alarm and notification sounds stay silent (%s)\n' \
    "$(distro_install_hint "$distro" sound-theme-freedesktop)"
fi
if [[ -r "$project_dir/zsh/.zshrc" ]]; then
  printf 'ok       session zshrc: %s\n' "$project_dir/zsh/.zshrc"
else
  missing session-zshrc "session zshrc: $project_dir/zsh/.zshrc" required
fi
if [[ -r "$fastfetch_config" ]]; then
  printf 'present  %s\n' "$fastfetch_config"
  logo=$(jq -r '.logo.source? // empty' "$fastfetch_config" 2>/dev/null || true)
  if [[ -n "$logo" && -r "${logo/#\~/$HOME}" ]]; then
    printf 'present  Fastfetch logo image\n'
  elif [[ -n "$logo" ]]; then
    missing fastfetch-logo "Fastfetch logo image: $logo"
  fi
else
  printf 'absent   %s (run install/install.sh --apply to copy it)\n' "$fastfetch_config"
fi

# The launcher's conversions ("10 km to mi") ask qalc, and the screenshots'
# text mode (Super+Alt+T) reads with tesseract and its English or German
# data - Arch's tesseract brings only "osd". Optional: without them those two
# say so and nothing else changes.
printf '\nLauncher and screenshots (optional)\n'
if command -v qalc >/dev/null 2>&1; then
  printf 'ok       qalc: %s\n' "$(command -v qalc)"
else
  missing qalc "qalc (conversions in the launcher; $(distro_install_hint "$distro" "$(package_for libqalculate libqalculate qalculate)"))"
fi
ocr_data=$(package_for "tesseract-data-eng tesseract-data-deu" "tesseract-langpack-eng tesseract-langpack-deu" \
  "tesseract-ocr-traineddata-english tesseract-ocr-traineddata-german")
if ! command -v tesseract >/dev/null 2>&1; then
  missing tesseract "tesseract (text from the screen; $(distro_install_hint "$distro" "$(package_for tesseract tesseract tesseract-ocr) $ocr_data"))"
elif tesseract_langs=$(tesseract --list-langs 2>/dev/null) && grep -qxE 'eng|deu' <<<"$tesseract_langs"; then
  printf 'ok       tesseract: %s\n' "$(command -v tesseract)"
else
  missing tesseract-data "tesseract's English or German data (text from the screen; $(distro_install_hint "$distro" "$ocr_data"))"
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
      finding note plocate-home "plocate has nothing under $HOME, so the launcher finds no files: $HOME is a btrfs subvolume, which updatedb skips as a bind mount" \
        "sudo sed -i -e 's/^PRUNE_BIND_MOUNTS *= *.*/PRUNE_BIND_MOUNTS = \"no\"/' -e '/^PRUNENAMES/{/\\.snapshots/!s/\"\$/ .snapshots\"/}' $updatedb_conf && sudo systemctl start plocate-updatedb.service"
      printf '         (%s is a btrfs subvolume, which updatedb skips as a bind mount):\n' "$HOME"
      printf "         sudo sed -i -e 's/^PRUNE_BIND_MOUNTS *= *.*/PRUNE_BIND_MOUNTS = \"no\"/' -e '/^PRUNENAMES/{/\\.snapshots/!s/\"\$/ .snapshots\"/}' %s\n" "$updatedb_conf"
      printf '         sudo systemctl start plocate-updatedb.service\n'
    else
      finding note plocate-home "plocate has nothing under $HOME, so the launcher finds no files (the index may be new or empty)" \
        "sudo systemctl start plocate-updatedb.service"
      printf '         (the index may be new or empty): sudo systemctl start plocate-updatedb.service\n'
    fi
  fi
fi

# A folder of the user's own icons (Brave puts its web apps' in
# ~/.local/share/icons/hicolor) without a current icon-theme.cache: Qt then
# tries every directory the theme's index names, twice per icon name the first
# time it is looked up - 39,000 failed file checks on the first launcher open
# of a session here (19.10., strace). The cache is the user's file, and the
# next web app makes it stale again, so it is said rather than written. Bash
# only: the test runs this with a PATH of stand-ins.
icon_dirs=()
for theme_dir in "${XDG_DATA_HOME:-$HOME/.local/share}"/icons/*/; do
  theme_dir=${theme_dir%/}
  compgen -G "$theme_dir/*/*/*.png" >/dev/null || compgen -G "$theme_dir/*/*/*.svg" >/dev/null || continue
  cache=$theme_dir/icon-theme.cache
  for sub in "$theme_dir"/*/ "$theme_dir"/*/*/; do
    [[ -d $sub ]] || continue
    if [[ ! -e $cache || $sub -nt $cache ]]; then icon_dirs+=("$theme_dir"); break; fi
  done
done
if (( ${#icon_dirs[@]} )); then
  printf '\nIcons\n'
  for theme_dir in "${icon_dirs[@]}"; do
    finding note icon-cache "$theme_dir has icons but no current icon-theme.cache, so the first lookup of each icon checks every folder of the theme" \
      "gtk-update-icon-cache -f -t $theme_dir"
    printf 'note     %s has icons but no current icon-theme.cache, so the first lookup of each icon checks every folder of the theme:\n' "$theme_dir"
    printf '         gtk-update-icon-cache -f -t %s\n' "$theme_dir"
  done
fi

# A machine setting, said rather than changed: with transparent huge pages
# `always` the kernel backs mostly empty heap ranges with 2 MB pages, and the
# shell holds about twice its memory (15.10.: 340 against 180 MB). `madvise`
# gives them to the programs that ask, the usual setting on a desktop.
thp=/sys/kernel/mm/transparent_hugepage/enabled
if [[ -r $thp ]] && grep -q '\[always\]' "$thp"; then
  printf '\nMemory\n'
  finding note thp 'transparent huge pages are "always"; "madvise" halves the shell'"'"'s memory' "echo madvise | sudo tee $thp"
  printf 'note     transparent huge pages are "always"; "madvise" halves the shell'"'"'s memory:\n'
  printf '         echo madvise | sudo tee %s\n' "$thp"
fi

if (( json )); then printf '{"kind":"result","status":%d}\n' "$status" >&3; fi
exit "$status"
