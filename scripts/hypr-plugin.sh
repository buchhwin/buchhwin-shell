#!/usr/bin/env bash
set -euo pipefail

# The project's Hyprland plugin (hypr/plugins/xcursor-scale: X11 pointers at
# the right size while X11 is sharp), built against the Hyprland that is
# installed and loaded into the one that runs.
#
#   hypr-plugin.sh load     build when needed, then load (scripts/session-init.sh)
#   hypr-plugin.sh build    only build
#   hypr-plugin.sh status   what is built, for which Hyprland, and whether it is loaded
#
# **Why a plugin, and why built here.** The fix was a patch on a home-built
# Hyprland, and every upgrade of the package replaced that build - the
# pointer in Citrix was too big again until somebody rebuilt Hyprland. A
# plugin is compiled against the headers the package installs
# (/usr/include/hyprland, `pkg-config hyprland`) in about five seconds, so
# the login after an upgrade builds it anew and nobody has to. One build per
# Hyprland and per source, kept in the cache (it can always be made again).
#
# Hyprland refuses a plugin built for another version (the API hash), so a
# build that does not fit leaves the pointer big and nothing else; a build
# that fails says why in the log and the session carries on.
#
# Not for a Hyprland built in the home directory (install/build-hyprland-leap.sh):
# that one carries the patch itself, and the two would scale twice.

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
name=xcursor-scale
source_file=$project_dir/hypr/plugins/$name/main.cpp
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/buchhwin-shell/plugins
headers=/usr/include/hyprland/src/version.h
pkg_modules=(hyprland pixman-1 libdrm libinput wayland-server xkbcommon)

log() { printf 'hypr-plugin: %s\n' "$*" >&2; }

# The Hyprland on PATH is the one the session runs (the session launcher
# puts a home-built one first).
home_built() {
  local binary
  binary=$(command -v Hyprland 2>/dev/null) || return 1
  [[ $binary == "$HOME"/* ]]
}

# One build per installed Hyprland (its version line and its headers) and
# per source.
build_key() {
  { Hyprland --version 2>/dev/null | head -n 1; cat -- "$headers" "$source_file"; } | sha256sum | cut -c1-16
}

plugin_path() {
  printf '%s/%s/%s.so\n' "$cache_dir" "$(build_key)" "$name"
}

build() {
  if home_built; then
    log "the running Hyprland is built in the home directory and carries the patch; no plugin"
    return 0
  fi
  local missing=()
  command -v g++ >/dev/null || missing+=(g++)
  command -v pkg-config >/dev/null || missing+=(pkg-config)
  [[ -r $headers ]] || missing+=("$headers")
  if (( ${#missing[@]} )); then
    log "cannot build without: ${missing[*]}"
    return 1
  fi
  local target flags
  target=$(plugin_path)
  [[ -s $target ]] && return 0
  flags=$(pkg-config --cflags "${pkg_modules[@]}") || { log "pkg-config does not know ${pkg_modules[*]}"; return 1; }
  mkdir -p -- "$(dirname -- "$target")"
  local partial=$target.partial
  # shellcheck disable=SC2086 # pkg-config's flags are words on purpose
  if ! g++ -shared -fPIC --no-gnu-unique -std=c++26 -O2 -o "$partial" "$source_file" $flags; then
    rm -f -- "$partial"
    log "build failed for $(Hyprland --version 2>/dev/null | head -n 1)"
    return 1
  fi
  mv -f -- "$partial" "$target"
  # Older builds are for a Hyprland that is gone.
  local dir
  for dir in "$cache_dir"/*/; do
    [[ $dir == "$(dirname -- "$target")/" ]] || rm -rf -- "$dir"
  done
  log "built $target"
}

loaded() {
  hyprctl plugin list 2>/dev/null | grep -q "Plugin $name by"
}

load() {
  build || return 1
  home_built && return 0
  loaded && return 0
  local target answer
  target=$(plugin_path)
  answer=$(hyprctl plugin load "$target" 2>&1) || true
  if [[ $answer != ok* ]]; then
    log "Hyprland did not load $target: $answer"
    return 1
  fi
  log "loaded $target"
}

status() {
  local target
  target=$(plugin_path)
  printf 'hyprland: %s\n' "$(Hyprland --version 2>/dev/null | head -n 1)"
  if home_built; then
    printf 'plugin:   not used (home-built Hyprland with the patch)\n'
    return 0
  fi
  printf 'built:    %s\n' "$([[ -s $target ]] && printf '%s' "$target" || printf 'no')"
  printf 'loaded:   %s\n' "$(loaded && printf yes || printf no)"
}

case ${1:-load} in
  load) load ;;
  build) build ;;
  status) status ;;
  *) printf 'usage: hypr-plugin.sh load|build|status\n' >&2; exit 2 ;;
esac
