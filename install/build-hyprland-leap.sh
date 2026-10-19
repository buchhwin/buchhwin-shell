#!/usr/bin/env bash
# Hyprland for openSUSE Leap 16, built from source into your home directory.
#
# Leap packages no Hyprland, and the one community repository that did
# (home:Cic17:Backports:Leap16) was found broken: its Hyprland needs libraries
# the repository no longer has, and its libraries need a libinput, a
# libdisplay-info and a libjxl newer than Leap's. So the stack is built here,
# pinned to tags *and* their commits, and installed under one directory:
#
#   ~/.local/opt/buchhwin-hyprland     (BUCHHWIN_HYPRLAND_PREFIX)
#
# Nothing of it goes into /usr, /usr/local or /opt. That matters for more than
# tidiness: Leap's ld.so.conf includes /usr/local/lib64, and the newer libinput
# and libxkbcommon Hyprland needs would be picked up there by every program on
# the system, KWin included. Here they are found only through the RUNPATH of
# what was built against them. The session launcher puts the prefix's bin/ in
# front of PATH when it exists (session/buchhwin-shell-session); the portal is
# registered through links in ~/.local/share. Root is needed for one thing
# only: the build dependencies, all from Leap's own repo-oss.
#
#   install/build-hyprland-leap.sh                 dry run (default)
#   install/build-hyprland-leap.sh --apply         dependencies, build, install
#   install/build-hyprland-leap.sh --apply --no-deps   build only (deps are there)
#   install/build-hyprland-leap.sh --apply --deps-only only the build dependencies
#   install/build-hyprland-leap.sh --apply --rebuild   build even when up to date
#   install/build-hyprland-leap.sh --status        what is installed
#   install/build-hyprland-leap.sh --remove        delete the prefix and the links
#   install/build-hyprland-leap.sh --list-packages the build dependencies
#
# Patches: install/patches/<component>/*.patch are applied to a clean
# checkout before building (currently Hyprland: XWayland cursors keep their
# size under xwayland:force_zero_scaling). A new, changed or removed patch
# makes the build out of date, and so does a changed build option.
#
# Hyprland's own dialogs (hyprland-guiutils, with its toolkit hyprtoolkit) are
# built too; Leap packages neither, and Hyprland starts them through PATH.
#
# A build run builds every component again and replaces the prefix as a whole.
# It refuses while a session runs from the prefix; build from Plasma or a TTY.
# The previous build is kept as PREFIX.previous until the next one.
set -euo pipefail

project_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
prefix=${BUCHHWIN_HYPRLAND_PREFIX:-"$HOME/.local/opt/buchhwin-hyprland"}
work=${XDG_CACHE_HOME:-"$HOME/.cache"}/buchhwin-shell/hyprland-build
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
apply=false
deps=true
rebuild=false
action=build
jobs=$(nproc 2>/dev/null || echo 4)

while (( $# )); do
  case "$1" in
    --apply) apply=true; shift ;;
    --no-deps) deps=false; shift ;;
    --deps-only) action=deps; shift ;;
    --rebuild) rebuild=true; shift ;;
    --status) action=status; shift ;;
    --remove) action=remove; shift ;;
    --list-packages) action=list; shift ;;
    --jobs) jobs=${2:?--jobs needs a number}; shift 2 ;;
    -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# Everything comes from repo-oss. gcc16 because Hyprland 0.56 is C++26 and
# uses library parts gcc15's libstdc++ does not have (std::ranges::starts_with
# stopped the first build there); Leap's libstdc++6 already comes from gcc16.
build_packages=(
  gcc16-c++ meson ninja cmake git pkgconf-pkg-config bison flex tar gzip
  # wayland and graphics
  wayland-devel libexpat-devel libxml2-devel libpixman-1-0-devel libdrm-devel libgbm-devel
  Mesa-libEGL-devel Mesa-libGLESv2-devel Mesa-libGLESv3-devel libglvnd-devel glslang-devel
  cairo-devel pango-devel librsvg-devel libjpeg8-devel libwebp-devel
  libpng16-devel file-devel liblcms2-devel
  # input and seat (libinput and libxkbcommon themselves are built below)
  libevdev-devel mtdev-devel systemd-devel libwacom-devel seatd-devel
  libdisplay-info-devel hwdata libei-devel
  # Hyprland itself
  libuuid-devel libXcursor-devel re2-devel muparser-devel libzip-devel
  tomlplusplus-devel pugixml-devel libffi-devel
  libxcb-devel xcb-util-devel xcb-util-wm-devel xcb-util-errors-devel
  xcb-util-renderutil-devel
  # the portal and its share picker
  pipewire-devel qt6-base-devel qt6-widgets-devel
  # hyprtoolkit, the toolkit Hyprland's dialogs are drawn with
  libiniparser-devel abseil-cpp-devel
  # runtime
  xwayland
)

# name|kind|source|tag|commit|options. In build order: each one may need the
# ones above it. kind: meson, cmake, lua.
components=(
  # Only the scanner, not libwayland: Leap's 1.24 fails wayland-protocols
  # 1.49's XML against its DTD. The system's libwayland stays the one in use.
  "wayland-scanner|meson|https://gitlab.freedesktop.org/wayland/wayland.git|1.26.0|87cc8a8728a923fc57938faa81ba0e74f34ecdc7|-Dlibraries=false -Dscanner=true -Dtests=false -Ddocumentation=false"
  "wayland-protocols|meson|https://gitlab.freedesktop.org/wayland/wayland-protocols.git|1.49|ee78491a237eaff9389a0ccf8680521d074407d3|-Dtests=false"
  "libxkbcommon|meson|https://github.com/xkbcommon/libxkbcommon.git|xkbcommon-1.13.2|d1442aaa6b635551182e83c3b55037f4c118c962|-Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false -Denable-xkbregistry=false -Dxkb-config-root=/usr/share/X11/xkb -Dx-locale-root=/usr/share/X11/locale"
  "libinput|meson|https://gitlab.freedesktop.org/libinput/libinput.git|1.29.2|917783150a5bab7d55eedc5714f1b49b192426ac|-Dlibwacom=true -Ddebug-gui=false -Dtests=false -Ddocumentation=false -Dudev-dir=@PREFIX@/lib/udev"
  "lua|lua|https://www.lua.org/ftp/lua-5.5.1.tar.gz|5.5.1|1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce|"
  "hyprwayland-scanner|cmake|https://github.com/hyprwm/hyprwayland-scanner.git|v0.4.6|b8632713a6beaf28b56f2a7b0ab2fb7088dbb404|"
  "hyprutils|cmake|https://github.com/hyprwm/hyprutils.git|v0.14.2|a21e87b878e72ee5dfd375899e8b2ad0d0c4c0e1|"
  "hyprlang|cmake|https://github.com/hyprwm/hyprlang.git|v0.6.8|3a1c1b25b059dae2c6bbc46991562ba1158d125c|"
  "hyprcursor|cmake|https://github.com/hyprwm/hyprcursor.git|v0.1.13|44e91d467bdad8dcf8bbd2ac7cf49972540980a5|"
  "hyprgraphics|cmake|https://github.com/hyprwm/hyprgraphics.git|v0.5.1|482d4b7ec36ffdaf3573086aa586b178fd5404be|"
  "hyprwire|cmake|https://github.com/hyprwm/hyprwire.git|v0.3.1|3e6865ce5fd9237b58f5b2ce5de18814df3baff5|"
  "aquamarine|cmake|https://github.com/hyprwm/aquamarine.git|v0.14.0|a79fb21b2e2a82dd061a6d071802bcf38bd5c383|"
  "Hyprland|cmake|https://github.com/hyprwm/Hyprland.git|v0.56.2|efb50993780079460b0cbed1363e2166a2de1d9f|"
  # Hyprland's dialogs: hyprland-dialog, -run, -update-screen, -donate-screen
  # and -welcome, started through PATH. guiutils 0.2.2 draws with hyprtoolkit;
  # Arch pairs it with hyprtoolkit 0.6.0, which is why hyprutils is 0.14.2.
  "hyprtoolkit|cmake|https://github.com/hyprwm/hyprtoolkit.git|v0.6.0|f8cbaf42e1f7fdc9c7565d7be3e935f6d56c7a39|"
  "hyprland-guiutils|cmake|https://github.com/hyprwm/hyprland-guiutils.git|v0.2.2|a16ad89ed5fb4192c966018a80c652de8d96f748|"
  "xdg-desktop-portal-hyprland|cmake|https://github.com/hyprwm/xdg-desktop-portal-hyprland.git|v1.4.1|cc8e5ef8fb2acef3db488b9a33b0c48c2a4ee204|"
)

# Links that make the portal visible to the user's session bus, systemd user
# manager and xdg-desktop-portal: link -> target, both below the homes.
portal_links=(
  "$data_home/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service|$prefix/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service"
  "$data_home/xdg-desktop-portal/portals/hyprland.portal|$prefix/share/xdg-desktop-portal/portals/hyprland.portal"
  "$data_home/systemd/user/xdg-desktop-portal-hyprland.service|$prefix/lib/systemd/user/xdg-desktop-portal-hyprland.service"
)

if [[ $action == list ]]; then
  printf '%s\n' "${build_packages[@]}"
  exit 0
fi

if (( EUID == 0 )); then
  printf 'Run this as yourself: everything is built and installed into your home directory.\n' >&2
  exit 2
fi

# shellcheck source=install/lib/distro.sh
. "$project_dir/install/lib/distro.sh"
distro=$(distro_detect) || exit 2
distro_untried "$distro" && exit 2

say() { printf '\n%s\n' "$1"; }
run() {
  if $apply; then
    printf '  + %s\n' "$*"
    "$@"
  else
    printf '  %s\n' "$*"
  fi
}

# By the executable, not the command line: start-hyprland runs `Hyprland`
# through PATH, so argv[0] is the bare name and never begins with the prefix.
session_running() {
  local pid exe
  for pid in $(pgrep -u "$(id -u)" 2>/dev/null); do
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
    [[ $exe == "$prefix"/* ]] && return 0
  done
  return 1
}

# Only a directory this script made may be moved or deleted: one that carries
# its build record, or an empty one. BUCHHWIN_HYPRLAND_PREFIX pointed at
# ~/.local would otherwise be one `--remove --apply` away from gone.
owned_prefix() {
  [[ ! -e $1 ]] || [[ -e $1/.buchhwin-build ]] || [[ -d $1 && -z $(ls -A -- "$1" 2>/dev/null) ]]
}

if [[ $action == status ]]; then
  if [[ -x $prefix/bin/Hyprland ]]; then
    printf 'installed  %s\n' "$("$prefix/bin/Hyprland" --version 2>/dev/null | head -n1)"
    printf 'prefix     %s\n' "$prefix"
    [[ -r $prefix/.buchhwin-build ]] && sed 's/^/built      /' "$prefix/.buchhwin-build"
  else
    printf 'not installed (%s)\n' "$prefix"
  fi
  for entry in "${portal_links[@]}"; do
    link=${entry%%|*}
    [[ -L $link ]] && printf 'linked     %s\n' "$link" || printf 'missing    %s\n' "$link"
  done
  exit 0
fi

if [[ $action == remove ]]; then
  for dir in "$prefix" "$prefix.previous"; do
    if ! owned_prefix "$dir"; then
      printf '%s was not built by this script (no .buchhwin-build); not removing it.\n' "$dir" >&2
      exit 1
    fi
  done
  if session_running; then
    printf 'A session runs from %s; log out of it first.\n' "$prefix" >&2
    exit 1
  fi
  for entry in "${portal_links[@]}"; do
    link=${entry%%|*}
    [[ -L $link ]] && run rm -f -- "$link"
  done
  [[ -e $prefix ]] && run rm -rf -- "$prefix"
  [[ -e $prefix.previous ]] && run rm -rf -- "$prefix.previous"
  $apply || printf '\nNothing was changed. Run with --apply to remove.\n'
  exit 0
fi

if [[ $distro != opensuse-leap ]]; then
  printf 'This builds Hyprland for openSUSE Leap 16; %s installs it as a package.\n' "$distro" >&2
  exit 2
fi

$apply || printf 'Dry run. These are the steps, in order:\n'

say "1. Build dependencies (${#build_packages[@]}, from repo-oss)"
if $deps; then
  # From repo-oss and nothing else: a third-party repository at the same
  # priority (X11:Wayland, found on the machine this was written on) offered
  # newer -devel packages whose libraries would have replaced the system's.
  oss=$(leap_oss_alias)
  if [[ -z $oss ]] && $apply; then
    printf '  No enabled repository serves Leap'"'"'s repo-oss; enable it first.\n' >&2
    exit 1
  fi
  oss=${oss:-repo-oss}
  zypper_repo_args=(--repo "$oss")
  pkg_install_safe "$distro" "${build_packages[@]}"
else
  printf '  skipped (--no-deps)\n'
fi
if [[ $action == deps ]]; then
  $apply || printf '\nNothing was changed. Run with --apply to install them.\n'
  exit 0
fi

say "2. Sources, pinned (into $work/src)"
for entry in "${components[@]}"; do
  IFS='|' read -r name kind url tag commit _ <<<"$entry"
  printf '  %-28s %-18s %s\n' "$name" "$tag" "${commit:0:12}"
done

# What a build records in PREFIX/.buchhwin-build, so a re-run (bootstrap.sh
# runs this every time) can tell that the pins have not moved.
# A component's patches and build options are part of what was built: an
# edited, added or removed patch, or a changed option, makes the build out
# of date. (The options' hash came in later than the rest; a prefix built
# before it is out of date once, for that reason alone.)
manifest() {
  local entry name tag commit options patch
  for entry in "${components[@]}"; do
    IFS='|' read -r name _ _ tag commit options <<<"$entry"
    printf '%s %s %s %s\n' "$name" "$tag" "${commit:0:12}" "$(printf '%s' "$options" | sha256sum | cut -c1-12)"
    for patch in "$project_dir/install/patches/$name"/*.patch; do
      [[ -e $patch ]] || continue
      printf '  %s %s\n' "${patch##*/}" "$(sha256sum "$patch" | cut -c1-12)"
    done
  done
}
up_to_date=false
if ! $rebuild && [[ -x $prefix/bin/Hyprland && -r $prefix/.buchhwin-build ]] \
    && [[ $(cat -- "$prefix/.buchhwin-build") == "$(manifest)" ]]; then
  up_to_date=true
fi

# checkout_component NAME URL TAG COMMIT SRC: SRC as the pinned commit with
# this project's patches for NAME on top (install/patches/NAME/*.patch, in
# name order). A cached checkout of the pin is reused, but always as a clean
# tree: one that still carried an earlier version of a patch failed to apply
# the edited one on every later run, and one with a patch since removed
# built it in all the same. SRC is this script's own cache. Every step says
# `|| return 1`: set -e alone would end the script inside the function,
# where the ERR trap that restores the previous build does not run.
checkout_component() {
  local name=$1 url=$2 tag=$3 commit=$4 src=$5 patch
  if [[ ! -d $src/.git ]] || [[ $(git -C "$src" rev-parse HEAD 2>/dev/null) != "$commit" ]]; then
    rm -rf -- "$src"
    logged git clone --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules "$url" "$src" || return 1
  fi
  if [[ $(git -C "$src" rev-parse HEAD) != "$commit" ]]; then
    printf '  %s %s is commit %s, not the pinned %s\n' "$name" "$tag" "$(git -C "$src" rev-parse HEAD)" "$commit" >&2
    return 1
  fi
  logged git -C "$src" reset -q --hard "$commit" || return 1
  logged git -C "$src" clean -qfdx || return 1
  logged git -C "$src" submodule foreach --quiet --recursive 'git reset -q --hard && git clean -qfdx' || return 1
  for patch in "$project_dir/install/patches/$name"/*.patch; do
    [[ -e $patch ]] || continue
    printf '  patch %s\n' "${patch##*/}"
    logged git -C "$src" apply "$patch" || return 1
  done
}

say "3. Build and install into $prefix"
if $up_to_date; then
  printf '  up to date (%s); --rebuild builds it again\n' "$("$prefix/bin/Hyprland" --version 2>/dev/null | head -n1 | cut -d' ' -f1,2)"
fi
if ! $apply && ! $up_to_date; then
  printf '  %d components with gcc-16, %d jobs; the previous build is kept as %s.previous\n' \
    "${#components[@]}" "$jobs" "$prefix"
fi

if $apply && ! $up_to_date; then
  if session_running; then
    printf '  A session runs from %s; build from Plasma or a TTY.\n' "$prefix" >&2
    exit 1
  fi
  command -v g++-16 >/dev/null 2>&1 || { printf '  g++-16 is missing; run with --deps-only first.\n' >&2; exit 1; }

  mkdir -p -- "$work/src" "$work/build"
  for dir in "$prefix" "$prefix.previous"; do
    if ! owned_prefix "$dir"; then
      printf '  %s was not built by this script (no .buchhwin-build); refusing to replace it.\n' "$dir" >&2
      exit 1
    fi
  done
  if [[ -e $prefix ]]; then
    rm -rf -- "$prefix.previous"
    mv -- "$prefix" "$prefix.previous"
    printf '  + kept the previous build as %s.previous\n' "$prefix"
  fi
  mkdir -p -- "$prefix"
  # Should any step fail, the previous build comes back rather than half of a
  # new one.
  # Interrupted too (Ctrl-C, a closed terminal): otherwise the next run took
  # the half-built prefix for the previous build and deleted the good one.
  restore() {
    trap - ERR INT TERM HUP
    printf '\n  The build did not finish; %s is as it was before.\n' "$prefix" >&2
    rm -rf -- "$prefix"
    if [[ -e $prefix.previous ]]; then mv -- "$prefix.previous" "$prefix"; fi
  }
  trap restore ERR
  trap 'restore; exit 130' INT TERM HUP

  # Each component's output goes to its own log; a failure prints its end.
  logs="$work/logs"
  mkdir -p -- "$logs"
  current_log=""
  logged() {
    if ! "$@" >>"$current_log" 2>&1; then
      printf '  failed: %s\n  last lines of %s:\n' "$*" "$current_log" >&2
      tail -n 25 -- "$current_log" | sed 's/^/    /' >&2
      return 1
    fi
  }

  export CC=gcc-16 CXX=g++-16
  export PATH="$prefix/bin:$PATH"
  export PKG_CONFIG_PATH="$prefix/lib64/pkgconfig:$prefix/lib/pkgconfig:$prefix/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  export CMAKE_PREFIX_PATH="$prefix"
  # RUNPATH on everything, so the private libinput and libxkbcommon are the
  # only ones in the process - aquamarine and Hyprland must not load two.
  export LDFLAGS="-Wl,-rpath,$prefix/lib64 -Wl,--enable-new-dtags ${LDFLAGS:-}"
  export LD_LIBRARY_PATH="$prefix/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

  for entry in "${components[@]}"; do
    IFS='|' read -r name kind url tag commit options <<<"$entry"
    options=${options//@PREFIX@/$prefix}
    src="$work/src/$name"
    build="$work/build/$name"
    printf '  == %-28s %s\n' "$name" "$tag"
    current_log="$logs/$name.log"
    : >"$current_log"
    if [[ $kind == lua ]]; then
      archive="$work/src/lua-$tag.tar.gz"
      [[ -s $archive ]] || logged curl -fsSL --retry 3 -o "$archive" "$url"
      if [[ $(sha256sum "$archive" | cut -d' ' -f1) != "$commit" ]]; then
        rm -f -- "$archive"
        printf '  %s does not match its checksum\n' "$archive" >&2
        false
      fi
      rm -rf -- "$src" && mkdir -p -- "$src"
      tar -xzf "$archive" -C "$src" --strip-components=1
      logged make -C "$src" -j"$jobs" linux CC=gcc-16 MYCFLAGS=-fPIC
      logged make -C "$src" install INSTALL_TOP="$prefix" INSTALL_LIB="$prefix/lib64"
      mkdir -p -- "$prefix/lib64/pkgconfig"
      # Lua ships no pkg-config file; Hyprland looks for lua55.
      cat >"$prefix/lib64/pkgconfig/lua55.pc" <<PC
prefix=$prefix
libdir=\${prefix}/lib64
includedir=\${prefix}/include

Name: Lua
Description: Lua $tag, static, for Hyprland
Version: $tag
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
PC
      continue
    fi
    checkout_component "$name" "$url" "$tag" "$commit" "$src"
    rm -rf -- "$build"
    case $kind in
      meson)
        # shellcheck disable=SC2086
        logged meson setup "$build" "$src" --prefix="$prefix" --libdir=lib64 --buildtype=release \
          -Db_lto=false $options
        logged ninja -C "$build" -j"$jobs"
        logged ninja -C "$build" install ;;
      cmake)
        # shellcheck disable=SC2086
        logged cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_INSTALL_RPATH="$prefix/lib64" -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
          -DBUILD_TESTING=OFF $options
        logged cmake --build "$build" -j"$jobs"
        logged cmake --install "$build" ;;
    esac
  done
  trap - ERR INT TERM HUP

  manifest >"$prefix/.buchhwin-build"
fi

if $apply; then
  say '4. The portal, registered for this user'
  for entry in "${portal_links[@]}"; do
    link=${entry%%|*}
    target=${entry#*|}
    if [[ -e $target ]]; then
      mkdir -p -- "${link%/*}"
      ln -sfn -- "$target" "$link"
      printf '  + %s\n' "$link"
    else
      printf '  missing %s (the portal did not install it)\n' "$target" >&2
    fi
  done
  systemctl --user daemon-reload 2>/dev/null || true

  printf '\nDone: %s\n' "$("$prefix/bin/Hyprland" --version 2>/dev/null | head -n1 | cut -d' ' -f1,2)"
  printf 'The buchhwin-shell session finds it there; nothing outside your home changed\n'
  printf 'except the build dependencies. To undo: %s --remove --apply\n' "$0"
else
  say '4. The portal, registered for this user'
  for entry in "${portal_links[@]}"; do
    printf '  link %s\n' "${entry%%|*}"
  done
  printf '\nNothing was changed. Run %s --apply to continue.\n' "$0"
fi
