#!/usr/bin/env bash
set -euo pipefail

# install/bootstrap.sh, against its dry run. The dry run is the whole test
# surface here on purpose: --apply installs packages, reaches the network and
# writes into $HOME, none of which belongs in a suite that has to be safe to
# run on the machine it is developed on.
#
# What is deliberately NOT tested: that every package name exists in the
# repositories (needs the network) and that the script refuses to run as root
# (`EUID` is readonly in bash and cannot be stubbed). The first is a manual
# check noted in docs/testing.md; the second is one `if` at the top of the file.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
script="$project_dir/install/bootstrap.sh"
failures=0

check() {
  if eval "$2"; then :; else printf 'FAIL bootstrap: %s\n' "$1"; failures=$((failures + 1)); fi
}

# The machine's own repositories must not decide what the dry run prints: a
# zypper that knows none stands in for the real one. Nor its packages: the
# AUR step (3b) asks pacman whether brave-bin is installed, and finds paru or
# yay on PATH - a stand-in pacman answers as STUB_BRAVE says (installed or
# not), and a paru is there.
stub_bin=$(mktemp -d)
trap 'rm -rf -- "$stub_bin"' EXIT
printf '#!/bin/sh\nexit 1\n' >"$stub_bin/zypper"
cat >"$stub_bin/pacman" <<'P'
#!/bin/sh
case "$*" in
  "-Q brave-bin") [ "${STUB_BRAVE:-}" = installed ] ;;
  *) exit 1 ;;
esac
P
printf '#!/bin/sh\nexit 0\n' >"$stub_bin/paru"
chmod +x "$stub_bin/zypper" "$stub_bin/pacman" "$stub_bin/paru"
export PATH="$stub_bin:$PATH"

# ---- the dry run, per distribution ----------------------------------------
# --distro rather than the machine's own os-release, so the suite checks every
# system wherever it runs.
for distro in fedora opensuse-leap arch; do
  out=$("$script" --distro "$distro") || { printf 'FAIL bootstrap: the %s dry run exited non-zero\n' "$distro"; exit 1; }

  for step in \
    '1. What the package manager needs' '2. Repositories' '3. Packages' \
    '4. The fonts' '5. The shell itself' '6. The session entry' \
    '7. Default applications'; do
    check "$distro: the dry run names step '$step'" '[[ $out == *"$step"* ]]'
  done

  check "$distro: the dry run names the distribution" '[[ $out == *"Distribution: $distro"* ]]'
  check "$distro: the dry run says it changed nothing" '[[ $out == *"Nothing was changed"* ]]'
  check "$distro: the dry run runs nothing (no \"+ \" command lines)" '[[ $out != *$'"'"'\n  + '"'"'* ]]'

  # ---- the options -------------------------------------------------------
  minimal=$("$script" --distro "$distro" --minimal)
  check "$distro: --minimal leaves the extras out" '[[ $minimal != *wf-recorder* ]]'
  check "$distro: the default run has the extras" '[[ $out == *wf-recorder* ]]'
  check "$distro: --minimal leaves the applications out" '[[ $minimal != *brave-browser* ]]'
  check "$distro: the default run has the applications" '[[ $out == *brave-browser* ]]'
  check "$distro: --minimal says what it left out" '[[ $minimal == *"--minimal:"* ]]'
  # services/CalendarService.qml imports org.kde.plasma.PimCalendars, and
  # without it the shell does not load: "only what the shell needs" has it.
  check "$distro: --minimal installs kdepim-addons, which the calendar service cannot load without" \
    '[[ $minimal == *" kdepim-addons "* ]]'

  skipped=$("$script" --distro "$distro" --skip-apps)
  check "$distro: --skip-apps leaves the applications out" '[[ $skipped != *brave-browser* ]]'
  check "$distro: --skip-apps keeps the extras" '[[ $skipped == *wf-recorder* ]]'

  # ---- the lists ---------------------------------------------------------
  # Through --list-packages rather than by parsing the package files: the
  # list has one owner, and the flag is what docs/testing.md tells people to
  # check against the repositories, so it is worth holding to account here.
  all_packages=$("$script" --distro "$distro" --list-packages)
  count=$(printf '%s\n' "$all_packages" | wc -l)
  unique=$(printf '%s\n' "$all_packages" | sort -u | wc -l)
  check "$distro: --list-packages lists something" '[[ $count -gt 20 ]]'
  check "$distro: no package is listed twice ($count listed, $unique distinct)" '[[ $count -eq $unique ]]'
  check "$distro: no package name has a stray character" \
    '! printf "%s\n" "$all_packages" | grep -qvE "^[A-Za-z0-9][A-Za-z0-9._+-]*$"'
  # The flag has to ignore the filters, or the check it exists for would
  # silently skip whatever the current options leave out.
  check "$distro: --list-packages ignores --minimal" \
    '[[ $("$script" --distro "$distro" --list-packages --minimal) == "$all_packages" ]]'
done

fedora=$("$script" --distro fedora)
leap=$("$script" --distro opensuse-leap)
# The lists are captured, then searched (pitfall 15): bootstrap.sh writes one
# in some sixty writes, `grep -qx` quits at its match, the next write gets
# SIGPIPE, and pipefail turned a found hyprland into a failure under load -
# and, behind the `!`, a hyprland in Leap's list into a pass.
fedora_list=$("$script" --distro fedora --list-packages)
leap_list=$("$script" --distro opensuse-leap --list-packages)
check 'Fedora installs with dnf' '[[ $fedora == *"sudo dnf -y install"* && $fedora != *zypper* ]]'
check 'Fedora enables the Hyprland Copr' '[[ $fedora == *"copr enable sachesi/hyprland"* ]]'
check 'Leap installs with zypper' '[[ $leap == *"sudo zypper --non-interactive install --no-recommends"* && $leap != *"dnf "* ]]'
check 'Leap installs only from the repositories it names' \
  '[[ $leap == *"--repo repo-oss --repo quickshell-leap16 --repo brave-browser quickshell"* ]]'
check 'Leap adds the Quickshell repository below repo-oss' \
  '[[ $leap == *"--priority 120 https://download.opensuse.org/repositories/home:/AvengeMedia:"* ]]'
check 'Leap no longer adds the broken Hyprland repository' '[[ $leap != *"Cic17"* ]]'
check 'Leap fetches cliphist with a checksum (or has it already)' \
  '[[ $leap == *"download cliphist"*"sha256"* || $leap == *"cliphist is already installed"* ]]'
check 'Leap builds Hyprland, as a dry run in the dry run' \
  '[[ $leap == *"4b. Hyprland, built from source"*"Hyprland "*"v0.56.2"* && $leap != *"+ git clone"* ]]'
check 'Leap does not install Hyprland as a package' '! grep -qx hyprland <<<"$leap_list"'
check 'both Nerd Fonts are handled' '[[ $leap == *"FiraCode Nerd Font Propo"* && $leap == *"JetBrainsMono Nerd Font"* ]]'
check 'Fedora installs Hyprland as a package' 'grep -qx hyprland <<<"$fedora_list"'
check 'Fedora does not build anything' '[[ $fedora != *"built from source"* ]]'

arch=$("$script" --distro arch)
arch_list=$("$script" --distro arch --list-packages)
check 'Arch installs with pacman, asking first' \
  '[[ $arch == *"sudo pacman -S --needed hyprland quickshell"* && $arch != *"--noconfirm"* ]]'
check 'Arch uses neither dnf nor zypper' '[[ $arch != *"dnf "* && $arch != *zypper* ]]'
check 'Arch adds no repository and refreshes nothing on its own' '[[ $arch != *"pacman -Sy "* && $arch != *"addrepo"* ]]'
check 'Arch installs Hyprland and its portal as packages' \
  'grep -qx hyprland <<<"$arch_list" && grep -qx xdg-desktop-portal-hyprland <<<"$arch_list"'
check 'Arch does not build anything' '[[ $arch != *"built from source"* ]]'
check 'Arch takes Brave from the AUR, with the helper there is' '[[ $arch == *"3b. From the AUR"*"  paru -S --needed brave-bin"* ]]'
arch_brave=$(STUB_BRAVE=installed "$script" --distro arch)
check 'Arch leaves an installed brave-bin alone' \
  '[[ $arch_brave == *"3b. From the AUR"*"brave-bin is already installed"* && $arch_brave != *"paru -S"* ]]'
check 'the AUR package is not in the list CI resolves against the repositories' '! grep -qx brave-bin <<<"$arch_list"'
check 'Arch installs both Nerd Fonts as packages' \
  'grep -qx ttf-firacode-nerd <<<"$arch_list" && grep -qx ttf-jetbrains-mono-nerd <<<"$arch_list"'
check 'Arch installs checkupdates for the update check, and the fakeroot it syncs through' \
  'grep -qx pacman-contrib <<<"$arch_list" && grep -qx fakeroot <<<"$arch_list"'
check 'Arch installs the MTP backend the drives list finds phones with' 'grep -qx gvfs-mtp <<<"$arch_list"'
check 'Arch installs merkuro, which the calendar service cannot load without' 'grep -qx merkuro <<<"$arch_list"'
check 'Arch installs rtkit, which PipeWire asks for realtime priority' 'grep -qx rtkit <<<"$arch_list"'

# org.kde.akonadi is akonadi-server's on Fedora, and no other package listed
# requires it: --minimal once installed a desktop without a shell.
fedora_minimal=$("$script" --distro fedora --minimal)
check 'Fedora --minimal installs akonadi-server, which ships the Akonadi QML module' \
  '[[ $fedora_minimal == *" akonadi-server "* ]]'
check 'Leap and Arch --minimal install merkuro (the Akonadi QML module on Leap, akonadi on Arch)' \
  '[[ $("$script" --distro opensuse-leap --minimal) == *" merkuro "* && $("$script" --distro arch --minimal) == *" merkuro "* ]]'
# setpriv (Paths.bound) is in util-linux or util-linux-core depending on the
# Fedora release; util-linux requires util-linux-core, so it covers both.
check 'Fedora installs util-linux for setpriv, not util-linux-core alone' \
  'grep -qx util-linux <<<"$fedora_list" && ! grep -qx util-linux-core <<<"$fedora_list"'

# Detection from os-release, through the library the script uses.
lib="$project_dir/install/lib/distro.sh"
os_release=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin"' EXIT
detect() {
  printf '%s\n' "$1" >"$os_release/os-release"
  (unset BUCHHWIN_DISTRO; BUCHHWIN_OS_RELEASE="$os_release/os-release"; . "$lib"; distro_detect 2>/dev/null)
}
check 'Fedora is detected' '[[ $(detect "ID=fedora
VERSION_ID=44") == fedora ]]'
check 'Leap 16 is detected' '[[ $(detect "ID=\"opensuse-leap\"
VERSION_ID=\"16.0\"
PRETTY_NAME=\"openSUSE Leap 16.0\"") == opensuse-leap ]]'
check 'Leap 15 is refused' '! detect "ID=opensuse-leap
VERSION_ID=15.6" >/dev/null'
check 'Tumbleweed is refused' '! detect "ID=opensuse-tumbleweed" >/dev/null'
check 'Arch is detected' '[[ $(detect "NAME=\"Arch Linux\"
ID=arch
BUILD_ID=rolling") == arch ]]'
check 'an Arch derivative is refused (BUCHHWIN_DISTRO=arch is the way in)' '! detect "ID=endeavouros
ID_LIKE=arch" >/dev/null'
check 'Debian is refused' '! detect "ID=debian" >/dev/null'
check 'an unknown --distro is refused' '! "$script" --distro debian >/dev/null 2>&1'
# sudo drops the environment; the system step gets the distribution by hand.
check 'the system step is told the distribution through sudo' \
  '[[ $arch == *"sudo env BUCHHWIN_DISTRO=arch "*"/install/system-install.sh"* ]]'

# ---- Arch: pkg_install_safe against a stub pacman ----------------------------
# The check before an --apply install, called on its own with a `run` that
# only records - the real pacman never answers here. The stub says what -Qu
# and -S --print would, from the arguments safe() gives it, and logs every call.
pacman_bin=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin"' EXIT
cat >"$pacman_bin/pacman" <<'P'
#!/bin/sh
printf '%s\n' "$*" >>"$PACMAN_CALLS"
case "$*" in
  -Qu) [ -n "$STUB_QU" ] || exit 1; printf '%s\n' "$STUB_QU" ;;
  "-S --needed --print"*)
    [ -z "$STUB_PRINT_ERR" ] || printf '%s\n' "$STUB_PRINT_ERR" >&2
    printf 'quickshell 0.3.2-1\n'
    exit "$STUB_PRINT_EXIT" ;;
  *) exit 99 ;;
esac
P
chmod +x "$pacman_bin/pacman"
# safe QU PRINT_STDERR PRINT_EXIT: pkg_install_safe arch quickshell, as --apply
# would call it; prints what it said and "RUN ..." for what it would run.
safe() {
  (
    export PATH="$pacman_bin:$PATH" PACMAN_CALLS="$pacman_bin/calls" \
      STUB_QU=$1 STUB_PRINT_ERR=$2 STUB_PRINT_EXIT=${3:-0}
    apply=true
    run() { printf 'RUN %s\n' "$*"; }
    . "$lib"
    pkg_install_safe arch quickshell
  ) 2>&1
}
out=$(safe "" "") && safe_status=0 || safe_status=$?
check "Arch: an up-to-date system installs, pacman asking itself (status $safe_status: $out)" \
  '[[ $safe_status -eq 0 && $out == *"RUN sudo pacman -S --needed quickshell"* ]]'
out=$(safe "glibc 2.41-1 -> 2.42-1" "") && safe_status=0 || safe_status=$?
check "Arch: pending upgrades refuse the install (status $safe_status)" \
  '[[ $safe_status -eq 1 && $out != *RUN* && $out == *"sudo pacman -Syu first"* && $out == *glibc* ]]'
out=$(safe "pinned-app 25.08-1 -> 26.04-1 [ignored]" "") && safe_status=0 || safe_status=$?
check "Arch: a package held back with IgnorePkg is no pending upgrade (status $safe_status: $out)" \
  '[[ $safe_status -eq 0 && $out == *"RUN sudo pacman -S --needed quickshell"* ]]'
out=$(safe "" "warning: downgrading package quickshell (0.3.3-1 => 0.3.2-1)") && safe_status=0 || safe_status=$?
check "Arch: a downgrade in the preview refuses the install (status $safe_status)" \
  '[[ $safe_status -eq 1 && $out != *RUN* && $out == *"would downgrade"* ]]'
out=$(safe "" "error: target not found: nosuch" 1) && safe_status=0 || safe_status=$?
check "Arch: a name pacman cannot resolve refuses the install (status $safe_status)" \
  '[[ $safe_status -eq 1 && $out != *RUN* && $out == *"cannot resolve"* ]]'
check 'Arch: the check never refreshes the database (no -Sy)' \
  '[[ -s $pacman_bin/calls ]] && ! grep -qE "^-S[a-z]*y" "$pacman_bin/calls"'

# Captured, not read back from $?: under set -e a failing --help would end
# the script before the check, so the check could only ever pass.
help_status=0; "$script" --help >/dev/null 2>&1 || help_status=$?
check '--help exits 0' '[[ $help_status -eq 0 ]]'

set +e
"$script" --nonsense >/dev/null 2>&1
unknown=$?
set -e
check 'an unknown option exits 2' '[[ $unknown -eq 2 ]]'

# ---- the default applications --------------------------------------------
# Every category the installer sets has to be one default-apps.py knows, and
# every desktop id has to look like one.
known=$(grep -oP '^\s*\("\K[a-z]+' "$project_dir/scripts/default-apps.py")
while IFS=: read -r category desktop_id; do
  [[ -z $category ]] && continue
  check "default-apps.py knows the category '$category'" \
    'grep -qx -- "$category" <<<"$known"'
  check "'$category' is set to a desktop id" '[[ $desktop_id == *.desktop ]]'
done < <(sed -n '/^app_defaults=(/,/^)/p' "$script" | grep -oP '"\K[^"]+(?=")')

# The file manager comes first: it is the category a session without a
# choice gets wrong.
order=$(sed -n '/^app_defaults=(/,/^)/p' "$script" | grep -oP '"\K[a-z]+(?=:)' | paste -sd' ')
check "the file manager is set before the browser ($order)" '[[ $order == "files browser"* ]]'

# ---- step 7 as --apply runs it -------------------------------------------------
# app_default, out of the script, against the real default-apps.py over an XDG
# tree of its own: Brave is not installed (Arch's AUR step went on without a
# helper), Dolphin and Ark are, and kitty's hidden helper comes first in the
# system's cache. The browser first, the worst order: a refused id ended the
# whole run there once, under set -e, before the file manager was set.
xdg=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg"' EXIT
mkdir -p "$xdg/data/applications" "$xdg/config"
desktop_entry() { printf '[Desktop Entry]\nType=Application\nName=%s\n%s\n' "$2" "$3" > "$xdg/data/applications/$1"; }
desktop_entry org.kde.dolphin.desktop Dolphin $'Categories=System;FileManager;\nMimeType=inode/directory;'
desktop_entry kitty-open.desktop 'kitty URL Launcher' $'NoDisplay=true\nMimeType=inode/directory;'
desktop_entry org.kde.ark.desktop Ark 'Categories=Utility;Archiving;'
printf '[MIME Cache]\ninode/directory=kitty-open.desktop;org.kde.dolphin.desktop;\n' > "$xdg/data/applications/mimeinfo.cache"
step7() {
  (
    set -euo pipefail
    export XDG_CONFIG_HOME="$xdg/config" XDG_DATA_HOME="$xdg/no-data" XDG_DATA_DIRS="$xdg/data" \
      XDG_CONFIG_DIRS="$xdg/no-etc" XDG_CURRENT_DESKTOP=buchhwin-shell:Hyprland
    defaults_tool="$project_dir/scripts/default-apps.py"
    eval "$(sed -n '/^app_default() {/,/^}/p' "$script")"
    for entry in "$@"; do app_default "${entry%%:*}" "${entry#*:}"; done
    printf 'end\n'
  ) 2>&1
}
step7_status=0
step7_out=$(step7 browser:brave-browser.desktop files:org.kde.dolphin.desktop archives:org.kde.ark.desktop) || step7_status=$?
session_list="$xdg/config/buchhwin-shell-mimeapps.list"
check "step 7 goes on past an application that is not installed (status $step7_status: $step7_out)" \
  '[[ $step7_status -eq 0 && $step7_out == *"browser   brave-browser.desktop is not installed; skipped"*end ]]'
check 'the file manager is Dolphin, never kitty'"'"'s helper' '[[ $step7_out == *"files     keeps org.kde.dolphin.desktop"* ]]'
check 'a category without a default gets the one named' \
  '[[ $step7_out == *"+ archives  org.kde.ark.desktop"* ]] && grep -qx "application/zip=org.kde.ark.desktop;" "$session_list"'
check 'nothing is written for the browser' '! grep -q brave "$session_list"'
# kitty's helper named in a mimeapps.list (Plasma's, say) is still no file
# manager for this session.
printf '[Default Applications]\ninode/directory=kitty-open.desktop;\n' > "$xdg/config/mimeapps.list"
step7_out=$(step7 files:org.kde.dolphin.desktop) || true
check "kitty's helper as a choice is replaced ($step7_out)" \
  '[[ $step7_out == *"+ files     org.kde.dolphin.desktop"* ]] && grep -qx "inode/directory=org.kde.dolphin.desktop;" "$session_list"'

# ---- what a system without Plasma needs -----------------------------------
# Each of these came only through Plasma's own packages: without them a fresh
# install had no sound card (pipewire-audio's ALSA devices), no PulseAudio
# clients, no WebP wallpapers, no Bluetooth daemon, no Notification portal,
# no emoji, no user directories, no power profiles and no NetworkManager
# secret agent.
for package in pipewire-audio pipewire-pulse qt6-imageformats bluez xdg-desktop-portal-gtk \
  noto-fonts-emoji xdg-user-dirs power-profiles-daemon network-manager-applet plasma-nm; do
  check "Arch installs $package" 'grep -qx "$package" <<<"$arch_list"'
done
for package in qt6-qtimageformats bluez xdg-desktop-portal-gtk google-noto-color-emoji-fonts xdg-user-dirs \
  network-manager-applet plasma-nm zsh-autosuggestions zsh-syntax-highlighting; do
  check "Fedora installs $package" 'grep -qx "$package" <<<"$fedora_list"'
done
for package in qt6-imageformats bluez xdg-desktop-portal-gtk google-noto-coloremoji-fonts xdg-user-dirs \
  NetworkManager-applet plasma6-nm; do
  check "Leap installs $package" 'grep -qx "$package" <<<"$leap_list"'
done
# Not in Leap 16.0's repo-oss: the run would stop at a name zypper cannot find.
check 'Leap does not ask for the zsh plugins repo-oss lacks' \
  '! grep -qxE "zsh-(autosuggestions|syntax-highlighting)" <<<"$leap_list"'

# ---- --skip-fonts ------------------------------------------------------------
# "Leave fonts alone": the font packages too, not only the download - Arch's
# two Nerd Fonts alone are some 230 MB. --list-packages still names them.
arch_nofonts=$("$script" --distro arch --skip-fonts)
check 'Arch --skip-fonts installs no font package' \
  '[[ $arch_nofonts != *ttf-firacode-nerd* && $arch_nofonts != *inter-font* && $arch_nofonts == *"--skip-fonts: the font packages are left out"* ]]'
check 'Arch installs the font packages without --skip-fonts' '[[ $arch == *ttf-firacode-nerd* ]]'
check 'Fedora --skip-fonts installs no font package' '[[ $("$script" --distro fedora --skip-fonts) != *rsms-inter-fonts* ]]'
check '--list-packages still names the font packages' \
  'grep -qx ttf-firacode-nerd <<<"$arch_list" && grep -qx rsms-inter-fonts <<<"$fedora_list"'

# ---- the Nerd Fonts, pinned ----------------------------------------------------
# One release and a sha256 per archive, like the fetched binaries; never
# "latest". A stand-in fc-list finds no font, so the dry run names the
# downloads even on a machine that has both faces.
fontless_bin=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg" "$fontless_bin"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$fontless_bin/fc-list"
chmod +x "$fontless_bin/fc-list"
leap_fonts=$(PATH="$fontless_bin:$PATH" "$script" --distro opensuse-leap)
check 'the dry run downloads the Nerd Fonts from a pinned release' \
  '[[ $leap_fonts == *"nerd-fonts/releases/download/v"*"/FiraCode.zip (Nerd Fonts v"*", sha256 "* && $leap_fonts != *"releases/latest"* ]]'
font_entries=$(sed -n '/^nerd_fonts=(/,/^)/p' "$script" | grep -oP '^\s*"\K[^"]+')
check 'there are two Nerd Fonts entries' '[[ $(grep -c . <<<"$font_entries") -eq 2 ]]'
while IFS='|' read -r _ archive _ _ sum; do
  check "$archive carries a sha256" '[[ $sum =~ ^[0-9a-f]{64}$ ]]'
done <<<"$font_entries"

# ---- Leap: which repositories get their keys trusted ----------------------------
# --gpg-auto-import-keys holds for every repository a refresh reads, so it is
# given only with the ones this run adds. A stand-in zypper that knows every
# alias stands for a machine where all of them are configured already.
check 'Leap trusts the keys of the repositories it adds, by name' \
  '[[ $leap == *"--gpg-auto-import-keys refresh quickshell-leap16 brave-browser"* ]]'
configured_bin=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg" "$fontless_bin" "$configured_bin"' EXIT
cat > "$configured_bin/zypper" <<'Z'
#!/bin/sh
case "$*" in
  "--non-interactive lr "*) exit 0 ;;
  *) exit 1 ;;
esac
Z
chmod +x "$configured_bin/zypper"
leap_configured=$(PATH="$configured_bin:$PATH" "$script" --distro opensuse-leap)
check 'Leap with every repository configured auto-imports no key' \
  '[[ $leap_configured == *"quickshell-leap16: already configured"* && $leap_configured != *gpg-auto-import-keys* ]]'

# ---- Leap 16.x after 16.0 ----------------------------------------------------------
# The lists were checked against 16.0: the installers refuse a later release
# unless BUCHHWIN_DISTRO lets it in, and then it finds its own repo-oss. The
# session's scripts (doctor, session-check) still know it for what it is.
check 'a later Leap 16.x is still Leap to the session scripts' '[[ $(detect "ID=opensuse-leap
VERSION_ID=16.1") == opensuse-leap ]]'
untried() {   # untried VERSION [BUCHHWIN_DISTRO]: distro_untried for that release
  printf 'ID=opensuse-leap\nVERSION_ID=%s\n' "$1" > "$os_release/os-release"
  (unset BUCHHWIN_DISTRO; [[ -n ${2:-} ]] && export BUCHHWIN_DISTRO=$2
   BUCHHWIN_OS_RELEASE="$os_release/os-release"; . "$lib"; distro_untried opensuse-leap) 2>&1
}
leap161_reason=$(untried 16.1) && leap161=0 || leap161=$?
check "the installers refuse Leap 16.1 and say the way in ($leap161: $leap161_reason)" \
  '[[ $leap161 -eq 0 && $leap161_reason == *"BUCHHWIN_DISTRO=opensuse-leap"* ]]'
check 'BUCHHWIN_DISTRO lets Leap 16.1 in' '! untried 16.1 opensuse-leap >/dev/null'
check 'Leap 16.0 needs nothing' '! untried 16.0 >/dev/null'
leap161_bin=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg" "$fontless_bin" "$configured_bin" "$leap161_bin"' EXIT
cat > "$leap161_bin/zypper" <<'Z'
#!/bin/sh
case "$*" in
  *" lr -u"*) printf '# | Alias | Name | Enabled | GPG Check | Refresh | URI\n'
              printf '1 | openSUSE:repo-oss | Main | Yes | (r ) Yes | Yes | http://download.opensuse.org/distribution/leap/16.1/repo/oss/\n' ;;
  *) exit 1 ;;
esac
Z
chmod +x "$leap161_bin/zypper"
check 'repo-oss of a later 16.x is found by its URL' \
  '[[ $(PATH="$leap161_bin:$PATH"; . "$lib"; leap_oss_alias) == openSUSE:repo-oss ]]'
check 'the Quickshell repository follows the release zypper runs' \
  '[[ $leap == *"/danklinux/\$releasever/ quickshell-leap16"* ]]'

# ---- Arch: what installed packages provide already ---------------------------------
# pacman -S --needed compares names only: a quickshell-git from the AUR made
# pacman ask "Remove quickshell-git?", and the default answer ended the run.
# Only the names `pacman -T` reports unsatisfied are installed; the stand-in
# answers -T from STUB_MISSING and -Qq from STUB_OWNER (DEPENDENCY=OWNER).
provides_bin=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg" "$fontless_bin" "$configured_bin" "$leap161_bin" "$provides_bin"' EXIT
cat > "$provides_bin/pacman" <<'P'
#!/bin/sh
printf '%s\n' "$*" >>"$PACMAN_CALLS"
case "$1" in
  -T) shift; status=0
      for dependency; do
        case " $STUB_MISSING " in *" $dependency "*) printf '%s\n' "$dependency"; status=127 ;; esac
      done
      exit "$status" ;;
  -Qq) for pair in $STUB_OWNER; do [ "${pair%%=*}" = "$2" ] && { printf '%s\n' "${pair#*=}"; exit 0; }; done
       printf '%s\n' "$2" ;;
  -Qu) exit 1 ;;
  -S) exit 0 ;;
  *) exit 99 ;;
esac
P
chmod +x "$provides_bin/pacman"
provided() {   # provided MISSING OWNERS PACKAGE...: pkg_install_safe arch, --apply
  (
    export PATH="$provides_bin:$PATH" PACMAN_CALLS="$provides_bin/calls" STUB_MISSING=$1 STUB_OWNER=$2
    shift 2
    apply=true
    run() { printf 'RUN %s\n' "$*"; }
    . "$lib"
    . "$project_dir/install/packages/arch.sh"
    pkg_install_safe arch "$@"
  ) 2>&1
}
out=$(provided "kitty" "quickshell=quickshell-git" quickshell kitty) && provided_status=0 || provided_status=$?
check "Arch installs only what nothing installed provides (status $provided_status: $out)" \
  '[[ $provided_status -eq 0 && $out == *"RUN sudo pacman -S --needed kitty"* && $out != *"--needed quickshell"* ]]'
check 'and says which installed package stands in' '[[ $out == *"quickshell: quickshell-git is installed and provides it; left alone"* ]]'
out=$(provided "" "pulse-native-provider=pulseaudio" pipewire-pulse) && provided_status=0 || provided_status=$?
check "PipeWire's PulseAudio server is left out where PulseAudio runs (status $provided_status: $out)" \
  '[[ $provided_status -eq 0 && $out != *RUN* && $out == *"pipewire-pulse: pulseaudio is installed"* ]]'
check 'it is asked for by what it provides' 'grep -qx -- "-T pulse-native-provider" "$provides_bin/calls"'
out=$(provided "pulse-native-provider" "" pipewire-pulse) && provided_status=0 || provided_status=$?
check "and installed where nothing provides a PulseAudio server (status $provided_status: $out)" \
  '[[ $out == *"RUN sudo pacman -S --needed pipewire-pulse"* ]]'
out=$(provided "" "" kitty quickshell) && provided_status=0 || provided_status=$?
check "a list that is all installed installs nothing (status $provided_status: $out)" \
  '[[ $provided_status -eq 0 && $out != *RUN* && $out == *"every package on the list is installed already"* ]]'
# A dry run where there is no pacman to ask (a preview on another system):
# a missing command exits 127 as well, the status of "some are missing", but
# names none, and the whole list read as installed already.
nopacman_bin="$provides_bin/nopacman"
mkdir -p "$nopacman_bin"
ln -s "$(command -v grep)" "$nopacman_bin/grep"
out=$( (apply=false; run() { printf 'RUN %s\n' "$*"; }; . "$lib"; PATH="$nopacman_bin"; pkg_install_safe arch kitty quickshell) 2>&1 ) || true
check "without a pacman to ask, the dry run names the whole list ($out)" \
  '[[ $out == *"RUN sudo pacman -S --needed kitty quickshell"* ]]'

# ---- Leap: a Hyprland build that does not happen ---------------------------------
# The build refuses while a session runs from its prefix (a re-run from the
# buchhwin session after a pin moved); steps 5-7 still run. A copy of the
# installers with a build script that always refuses.
refusing=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin" "$pacman_bin" "$xdg" "$fontless_bin" "$configured_bin" "$leap161_bin" "$provides_bin" "$refusing"' EXIT
mkdir -p "$refusing/install"
cp -r "$project_dir/install/lib" "$project_dir/install/packages" "$refusing/install/"
cp "$script" "$refusing/install/bootstrap.sh"
printf '#!/bin/sh\necho "  A session runs from the prefix; build from Plasma or a TTY." >&2\nexit 1\n' \
  > "$refusing/install/build-hyprland-leap.sh"
chmod +x "$refusing/install/build-hyprland-leap.sh"
refused_status=0
refused=$("$refusing/install/bootstrap.sh" --distro opensuse-leap 2>&1) || refused_status=$?
check "a refused Hyprland build does not end the run (status $refused_status)" \
  '[[ $refused_status -eq 0 && $refused == *"Hyprland was not built (status 1"*"5. The shell itself"*"6. The session entry"*"7. Default applications"* ]]'

if (( failures )); then
  printf 'TESTS FAILED bootstrap (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED bootstrap\n'
