#!/usr/bin/env bash
set -euo pipefail

# install/build-hyprland-leap.sh, against its dry run and its bookkeeping.
# Building is not tested here: it needs the build dependencies, the network and
# half an hour, none of which belongs in a suite that runs on every change.
# What is tested is everything around it - the pins, the package list, that it
# touches nothing outside its prefix and its three links, and that --remove
# removes exactly those.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
script="$project_dir/install/build-hyprland-leap.sh"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-buildtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$2"; then :; else printf 'FAIL build-hyprland: %s\n' "$1"; failures=$((failures + 1)); fi
}

home="$sandbox/home"
mkdir -p "$home"
in_sandbox() {
  env -u BUCHHWIN_HYPRLAND_PREFIX HOME="$home" XDG_DATA_HOME="$home/.local/share" \
    XDG_CACHE_HOME="$home/.cache" BUCHHWIN_DISTRO=opensuse-leap "$@"
}

# ---- the dry run ---------------------------------------------------------
out=$(in_sandbox "$script") || { printf 'FAIL build-hyprland: the dry run exited non-zero\n'; exit 1; }
check 'the dry run says it changed nothing' '[[ $out == *"Nothing was changed"* ]]'
check 'the dry run runs nothing' '[[ $out != *$'"'"'\n  + '"'"'* ]]'
check 'the dry run installs the build dependencies with zypper, from repo-oss only' \
  '[[ $out =~ "sudo zypper --non-interactive install --no-recommends --repo "[^\ ]*repo-oss" gcc16-c++" ]]'
check 'the dry run names Hyprland and its version' '[[ $out == *"Hyprland"*"v0.56.2"* ]]'
check 'the dry run names the dialogs and their version' '[[ $out == *"hyprland-guiutils"*"v0.2.2"* ]]'
check 'everything goes into the home directory' '[[ $out == *"into $home/.local/opt/buchhwin-hyprland"* ]]'
check 'the dry run created nothing' '[[ -z $(find "$home" -mindepth 1 -print -quit) ]]'

# ---- the pins --------------------------------------------------------------
# Every component: a tag and a full commit (git) or sha256 (the Lua archive).
pins=$(sed -n '/^components=(/,/^)/p' "$script" | grep -oP '^\s*"\K[^"]+')
count=$(grep -c . <<<"$pins")
check "16 components are pinned ($count)" '[[ $count -eq 16 ]]'
while IFS='|' read -r name kind url tag commit _; do
  case $kind in
    lua) check "$name is pinned to a sha256" '[[ $commit =~ ^[0-9a-f]{64}$ && $url == https://* ]]' ;;
    meson|cmake) check "$name is pinned to a full commit" '[[ $commit =~ ^[0-9a-f]{40}$ && $url == https://*.git ]]' ;;
    *) check "$name has a known kind ($kind)" 'false' ;;
  esac
  check "$name has a tag" '[[ -n $tag ]]'
done <<<"$pins"
# Order matters: what Hyprland links against is built before it.
order=$(cut -d'|' -f1 <<<"$pins" | paste -sd' ')
check 'libinput and libxkbcommon come before aquamarine and Hyprland' \
  '[[ $order == *libxkbcommon*libinput*aquamarine*Hyprland* ]]'
check 'the scanner comes before the protocols it generates' '[[ $order == wayland-scanner\ wayland-protocols* ]]'
check 'the portal comes last' '[[ $order == *" xdg-desktop-portal-hyprland" ]]'
check 'hyprtoolkit comes after aquamarine and before the dialogs it draws' \
  '[[ $order == *aquamarine*hyprtoolkit*hyprland-guiutils* ]]'

# ---- the package list --------------------------------------------------------
packages=$("$script" --list-packages)
check 'the build needs gcc 16' 'grep -qx gcc16-c++ <<<"$packages"'
check 'no build dependency is listed twice' '[[ $(sort <<<"$packages" | uniq -d) == "" ]]'
check 'no package name has a stray character' '! grep -qvE "^[A-Za-z0-9][A-Za-z0-9._+-]*$" <<<"$packages"'
check 'libinput is built, not installed' '! grep -qx libinput-devel <<<"$packages"'
check 'hyprtoolkit finds iniparser and abseil' \
  'grep -qx libiniparser-devel <<<"$packages" && grep -qx abseil-cpp-devel <<<"$packages"'

# ---- refusals ----------------------------------------------------------------
status=0; env HOME="$home" BUCHHWIN_DISTRO=fedora "$script" >/dev/null 2>&1 || status=$?
check 'it refuses on Fedora, where Hyprland is a package' '[[ $status -eq 2 ]]'
status=0; in_sandbox "$script" --nonsense >/dev/null 2>&1 || status=$?
check 'an unknown option exits 2' '[[ $status -eq 2 ]]'

# ---- status and remove --------------------------------------------------------
prefix="$home/.local/opt/buchhwin-hyprland"
mkdir -p "$prefix/bin" "$prefix/share/xdg-desktop-portal/portals" "$home/.local/share/xdg-desktop-portal/portals"
# A directory this script did not build is never removed, whatever the prefix
# variable says - BUCHHWIN_HYPRLAND_PREFIX=~/.local must not empty ~/.local.
foreign="$home/foreign"
mkdir -p "$foreign/keep"
status=0; env BUCHHWIN_HYPRLAND_PREFIX="$foreign" HOME="$home" XDG_DATA_HOME="$home/.local/share" BUCHHWIN_DISTRO=opensuse-leap \
  "$script" --remove --apply >/dev/null 2>&1 || status=$?
check '--remove refuses a directory without the build record' '[[ $status -ne 0 && -d $foreign/keep ]]'
touch "$prefix/.buchhwin-build"
touch "$prefix/share/xdg-desktop-portal/portals/hyprland.portal"
ln -s "$prefix/share/xdg-desktop-portal/portals/hyprland.portal" "$home/.local/share/xdg-desktop-portal/portals/hyprland.portal"
touch "$home/.local/share/xdg-desktop-portal/portals/kde.portal"
status_out=$(in_sandbox "$script" --status)
check '--status reports the link' '[[ $status_out == *"linked     $home/.local/share/xdg-desktop-portal/portals/hyprland.portal"* ]]'
dry=$(in_sandbox "$script" --remove)
check '--remove alone changes nothing' '[[ -d $prefix && $dry == *"Nothing was changed"* ]]'
in_sandbox "$script" --remove --apply >/dev/null
check '--remove --apply deletes the prefix' '[[ ! -e $prefix ]]'
check '--remove --apply deletes its link' '[[ ! -L $home/.local/share/xdg-desktop-portal/portals/hyprland.portal ]]'
check '--remove --apply leaves everything else' '[[ -e $home/.local/share/xdg-desktop-portal/portals/kde.portal ]]'

if (( failures )); then
  printf 'TESTS FAILED build-hyprland (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED build-hyprland\n'
