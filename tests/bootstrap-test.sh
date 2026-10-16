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
check 'Leap does not install Hyprland as a package' '! "$script" --distro opensuse-leap --list-packages | grep -qx hyprland'
check 'both Nerd Fonts are handled' '[[ $leap == *"FiraCode Nerd Font Propo"* && $leap == *"JetBrainsMono Nerd Font"* ]]'
check 'Fedora installs Hyprland as a package' '"$script" --distro fedora --list-packages | grep -qx hyprland'
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

# setpriv (Paths.bound) is in util-linux or util-linux-core depending on the
# Fedora release; util-linux requires util-linux-core, so it covers both.
fedora_list=$("$script" --distro fedora --list-packages)
# org.kde.akonadi is akonadi-server's on Fedora, and no other package listed
# requires it: --minimal once installed a desktop without a shell.
fedora_minimal=$("$script" --distro fedora --minimal)
check 'Fedora --minimal installs akonadi-server, which ships the Akonadi QML module' \
  '[[ $fedora_minimal == *" akonadi-server "* ]]'
check 'Leap and Arch --minimal install merkuro (the Akonadi QML module on Leap, akonadi on Arch)' \
  '[[ $("$script" --distro opensuse-leap --minimal) == *" merkuro "* && $("$script" --distro arch --minimal) == *" merkuro "* ]]'
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

if (( failures )); then
  printf 'TESTS FAILED bootstrap (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED bootstrap\n'
