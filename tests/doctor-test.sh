#!/usr/bin/env bash
set -euo pipefail

# scripts/doctor.sh on a PATH of stand-ins: which commands it looks for on
# which distribution, which hints it gives, what fails the run and what only
# says so - and that it never names another system's commands (an Arch
# derivative was told to install dnf5). The system bus is a stand-in busctl;
# the QML modules are a tree in the sandbox (BUCHHWIN_QT6_DIR).
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-doctortest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$2"; then :; else printf 'FAIL doctor: %s\n' "$1"; failures=$((failures + 1)); fi
}

# Only what the script itself needs from the system, linked in by name, and
# the commands under test as stand-ins: nothing of this machine's own
# installation decides a case.
bin="$sandbox/bin"
mkdir -p "$bin"
for tool in bash sed awk grep dirname cat tr head readlink; do
  real=$(command -v "$tool") || { printf 'doctor test: %s is missing\n' "$tool" >&2; exit 1; }
  ln -s "$real" "$bin/$tool"
done
stub() { for name in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$bin/$name"; chmod +x "$bin/$name"; done; }
# python3 is only asked for the Akonadi bindings, and the real one would
# answer for this machine (a Fedora with them installed): none here.
printf '#!/bin/sh\nexit 1\n' > "$bin/python3"; chmod +x "$bin/python3"
stub Hyprland hyprctl quickshell setpriv kitty zsh brightnessctl wpctl pw-metadata playerctl nmcli udevadm \
  jq swaylock curl gammastep checkupdates dnf5 zypper flatpak plasma-discover hyprland-dialog gtk-launch \
  fastfetch cmatrix cava xclip qalc
# tesseract with the data $TESS_LANGS names (English by default): the
# screenshots' text mode is there.
tesseract_stub() {
  cat > "$bin/tesseract" <<'EOF'
#!/bin/sh
[ "$1" = --list-langs ] || exit 0
echo 'List of available languages in "/usr/share/tessdata/" (2):'
for lang in ${TESS_LANGS-eng osd}; do echo "$lang"; done
EOF
  chmod +x "$bin/tesseract"
}
tesseract_stub
# plocate finds files under $HOME: the launcher's note stays out.
printf '#!/bin/sh\necho 5\n' > "$bin/plocate"; chmod +x "$bin/plocate"
# The system bus: what $BUS says, or no answer at all.
cat > "$bin/busctl" <<'EOF'
#!/bin/sh
[ -n "${BUS:-}" ] || exit 1
printf '%b' "$BUS"
EOF
chmod +x "$bin/busctl"
header='NAME PID PROCESS USER CONNECTION UNIT SESSION DESCRIPTION\n'
bus_all="${header}net.hadess.PowerProfiles 765 ppd root :1.13 ppd.service - -\norg.freedesktop.NetworkManager 682 NetworkManager root :1.3 NetworkManager.service - -\norg.bluez 683 bluetoothd root :1.4 bluetooth.service - -\n"
# NetworkManager installed but never enabled, BlueZ only activatable.
bus_off="${header}net.hadess.PowerProfiles - - - (activatable) - - -\norg.bluez - - - (activatable) - - -\n"

qt6="$sandbox/qt6"
for module in org/kde/plasma/PimCalendars org/kde/plasma/workspace/calendar org/kde/kitemmodels org/kde/akonadi; do
  mkdir -p "$qt6/qml/$module"
done
mkdir -p "$qt6/plugins/plasmacalendarplugins" && : > "$qt6/plugins/plasmacalendarplugins/pimevents.so"
home="$sandbox/home"
mkdir -p "$home/.config/xdg-desktop-portal"
printf '[preferred]\norg.freedesktop.impl.portal.Secret=kwallet\n' > "$home/.config/xdg-desktop-portal/buchhwin-shell-portals.conf"
os="$sandbox/os"
mkdir -p "$os"
printf 'ID=arch\n' > "$os/arch"
printf 'ID=cachyos\nID_LIKE=arch\n' > "$os/cachyos"
printf 'ID=fedora\nVERSION_ID=44\n' > "$os/fedora"
printf 'ID="opensuse-leap"\nVERSION_ID="16.0"\nID_LIKE="suse opensuse"\n' > "$os/leap"
printf 'ID=gentoo\n' > "$os/gentoo"

# doctor RELEASE [ENV...]: its output in $out, its status in $rc.
doctor() {
  local release=$1; shift
  rc=0
  out=$(env -i PATH="$bin" HOME="$home" XDG_CONFIG_HOME="$home/.config" BUCHHWIN_QT6_DIR="$qt6" \
          BUCHHWIN_OS_RELEASE="$os/$release" BUS="$bus_all" "$@" bash "$project_dir/scripts/doctor.sh" 2>&1) || rc=$?
}
has() { grep -qF -- "$1" <<<"$out"; }

# Arch, everything there but pw-record, Brave and Dolphin: the run passes,
# the backend names its package, and the applications are optional.
doctor arch
check 'Arch without pw-record, Brave and Dolphin passes' '[[ $rc -eq 0 ]]'
check 'and names pw-record'"'"'s package' 'has "missing  pw-record (some shell features stay unavailable; sudo pacman -S pipewire-audio)"'
check 'Brave and Dolphin are optional applications' 'has "Applications (optional)" && has "missing  brave-browser (optional; paru -S brave-bin (from the AUR))" && has "missing  dolphin (optional; sudo pacman -S dolphin)"'
check 'Arch looks for checkupdates, not dnf5' 'has "ok       checkupdates" && ! has dnf5'
check 'Arch does not look for Discover (Updates upgrades in a terminal there)' '! has plasma-discover'
check 'the services on the bus are found' 'has "ok       power profiles D-Bus service" && has "ok       NetworkManager" && has "ok       BlueZ"'
check 'Arch has no Akonadi Python bindings to miss' 'has "note     Akonadi Python bindings are not packaged for arch" && ! has "missing  Akonadi"'

# The launcher's conversions and the screenshots' text are optional: said,
# with this system's packages, and the run still passes.
check 'qalc and tesseract'"'"'s data are there' 'has "ok       qalc" && has "ok       tesseract"'
doctor arch TESS_LANGS="afr osd"
check 'tesseract without English or German data is said' \
  'has "missing  tesseract'"'"'s English or German data (text from the screen; sudo pacman -S tesseract-data-eng tesseract-data-deu)" && [[ $rc -eq 0 ]]'
rm "$bin/qalc" "$bin/tesseract"
doctor fedora
check 'without qalc and tesseract, in Fedora'"'"'s words' \
  'has "missing  qalc (conversions in the launcher; sudo dnf install libqalculate)" && has "sudo dnf install tesseract tesseract-langpack-eng tesseract-langpack-deu" && [[ $rc -eq 0 ]]'
stub qalc
tesseract_stub

# An Arch derivative is Arch here (the installers still refuse it).
doctor cachyos
check 'CachyOS gets Arch'"'"'s checks and hints' 'has "ok       checkupdates" && has "sudo pacman -S pipewire-audio"'
check 'and nothing of Fedora'"'"'s' '! grep -qiE "dnf|python3-kf6" <<<"$out"'

# Fedora and Leap: their own update tools and package names.
doctor fedora
check 'Fedora looks for dnf5 and Discover' 'has "ok       dnf5" && has "ok       plasma-discover"'
check 'and names its pipewire package' 'has "sudo dnf install pipewire-utils"'
check 'and the Akonadi Python bindings it packages' \
  'has "missing  Akonadi Python bindings (writing events unavailable; sudo dnf install python3-kf6-kcoreaddons python3-kf6-kcalendarcore)"'
doctor leap
check 'Leap looks for zypper' 'has "ok       zypper" && ! has dnf5'
check 'and names its pipewire package' 'has "sudo zypper install pipewire-tools"'

# A system nobody knows: no other system's commands, only package names.
doctor gentoo
check 'an unknown system passes' '[[ $rc -eq 0 ]]'
check 'and is told no dnf, zypper or pacman' '! grep -qE "dnf|zypper|pacman" <<<"$out" && has "package pipewire-audio"'

# NetworkManager installed but never enabled, BlueZ not running: said, with
# the command that starts them; a power profiles daemon that can be started
# counts. No system bus at all checks none of them.
doctor arch BUS="$bus_off"
check 'a stopped NetworkManager is said' 'has "missing  NetworkManager is not running" && has "sudo systemctl enable --now NetworkManager"'
check 'a stopped BlueZ is said' 'has "missing  BlueZ is not running" && has "sudo systemctl enable --now bluetooth"'
check 'an activatable power profiles daemon counts' 'has "ok       power profiles D-Bus service"'
check 'and none of it fails the run' '[[ $rc -eq 0 ]]'
doctor arch BUS=
check 'without a system bus nothing on it is called missing' 'has "skip     the system bus did not answer" && ! has "missing  power profiles" && ! has "missing  NetworkManager"'

# What the session cannot start without fails the run.
rm "$bin/kitty"
doctor arch
check 'a missing kitty fails the run' '[[ $rc -ne 0 ]] && has "missing  kitty"'
stub kitty
rm -r "$qt6/qml/org/kde/akonadi"
doctor arch
check 'a missing QML module fails the run' '[[ $rc -ne 0 ]] && has "missing  Akonadi QML module org.kde.akonadi"'
mkdir -p "$qt6/qml/org/kde/akonadi"

# Strict (a machine the whole list was installed on): every missing line
# fails, unless its id is allowed.
doctor arch BUCHHWIN_DOCTOR_STRICT=1
check 'strict fails on a missing backend' '[[ $rc -ne 0 ]]'
doctor arch BUCHHWIN_DOCTOR_STRICT=1 BUCHHWIN_DOCTOR_ALLOW="brave-browser dolphin"
check 'and still with the applications allowed' '[[ $rc -ne 0 ]]'
doctor arch BUCHHWIN_DOCTOR_STRICT=1 BUCHHWIN_DOCTOR_ALLOW="brave-browser dolphin pw-record kwallet-portal"
check 'and passes once every miss is allowed' '[[ $rc -eq 0 ]] || { printf "%s\n" "$out" | grep "^missing"; false; }'

# A user icon folder without a current icon-theme.cache: said, with the command.
icons="$home/.local/share/icons/hicolor"
mkdir -p "$icons/128x128/apps" && : > "$icons/128x128/apps/sample-app.png"
doctor arch
check 'an icon folder without a cache is named, with the command' 'has "gtk-update-icon-cache -f -t $icons"'
: > "$icons/icon-theme.cache"
touch -d '+1 minute' "$icons/icon-theme.cache"
doctor arch
check 'and not once its cache is newer than its folders' '! has "icon-theme.cache"'
rm -rf "$home/.local/share/icons"

if (( failures )); then
  printf 'TESTS FAILED doctor (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED doctor\n'
