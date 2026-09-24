#!/usr/bin/env bash
set -euo pipefail

# Optional, system-wide: stop BlueZ powering the adapter on at every boot, so
# Bluetooth is where you left it. Called by install/system-install.sh
# --bluetooth-manual / --bluetooth-auto.
#
#   bluetooth-autoenable.sh off|on|status [--root DIR]
#
# Reported as "Bluetooth was switched on again after the restart although I
# turned it off before". It is not the shell - nothing in `services/` powers an
# adapter on - it is BlueZ's own `[Policy] AutoEnable`, which defaults to
# **true** and is commented out in Fedora's `/etc/bluetooth/main.conf`. Every
# boot therefore powers the adapter up, whatever the last session did.
#
# A drop-in rather than an edit of main.conf: the package owns that file and an
# update would take an edit with it, while `main.conf.d/` is ours to keep.
# `on` removes the drop-in and BlueZ is back to its own default.
#
# --root DIR works below DIR without root rights (tests).

drop_dir=/etc/bluetooth/main.conf.d
drop_name=50-buchhwin-autoenable.conf
marker='# Managed by buchhwin-shell (install/bluetooth-autoenable.sh)'

action=${1:-}
shift || true
root=""
while (( $# )); do
  case "$1" in
    --root) root=${2:?--root needs a directory}; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n $root ]] && root=$(realpath -m -- "$root")
target="$root$drop_dir/$drop_name"

case "$action" in
  off)
    install -d -- "$(dirname -- "$target")"
    cat > "$target" <<CONF
$marker
#
# BlueZ powers the adapter on at every boot unless told not to; the default of
# [Policy] AutoEnable is true and Fedora ships it commented out. With this the
# adapter stays wherever the last session left it, which is what the shell's
# own Bluetooth switch then means.
[Policy]
AutoEnable=false
CONF
    chmod 0644 -- "$target"
    printf 'Wrote %s - Bluetooth stays where you leave it.\n' "$target"
    printf 'It takes effect on the next boot.\n'
    ;;
  on)
    if [[ -e $target ]] && grep -qF "$marker" "$target"; then
      rm -f -- "$target"
      printf 'Removed %s - BlueZ powers the adapter on at boot again.\n' "$target"
    else
      printf 'Nothing of this project at %s\n' "$target"
    fi
    ;;
  status)
    if [[ -e $target ]] && grep -qF "$marker" "$target"; then
      printf 'installed: %s\n' "$target"
      grep -hE '^\s*AutoEnable' "$target" 2>/dev/null || true
    else
      printf 'absent: %s (BlueZ decides, and its default is on)\n' "$target"
    fi
    ;;
  *)
    printf 'Usage: %s off|on|status [--root DIR]\n' "$0" >&2
    exit 2
    ;;
esac
