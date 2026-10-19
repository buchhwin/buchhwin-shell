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
# **true** and is commented out in the shipped `/etc/bluetooth/main.conf`.
# Every boot therefore powers the adapter up, whatever the last session did.
#
# In main.conf itself, because that is the only file bluetoothd reads: it has
# no main.conf.d/, and the drop-in an earlier version of this script wrote
# there changed nothing (it is removed here). The package manager keeps an
# edited main.conf over upgrades (pacman's .pacnew, rpm's %config). `off`
# keeps a copy of the file as it was (main.conf.before-buchhwin), comments out
# any AutoEnable line of its own in [Policy] and adds `AutoEnable=false` under
# a marker line; `on` takes exactly that back.
#
# --root DIR works below DIR without root rights (tests).

conf=/etc/bluetooth/main.conf
old_drop=/etc/bluetooth/main.conf.d/50-buchhwin-autoenable.conf
marker='# Managed by buchhwin-shell (install/bluetooth-autoenable.sh): Bluetooth stays where you leave it'
# What an AutoEnable line this script commented out starts with.
tag='#buchhwin-shell: '

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
target="$root$conf"
backup="$target.before-buchhwin"
stale="$root$old_drop"

# The drop-in of the earlier version, when it is that version's.
remove_stale_drop() {
  if [[ -e $stale ]] && grep -qF '# Managed by buchhwin-shell (install/bluetooth-autoenable.sh)' "$stale"; then
    rm -f -- "$stale"
    rmdir -- "$(dirname -- "$stale")" 2>/dev/null || true
    printf 'Removed %s, which BlueZ never read.\n' "$stale"
  fi
}

# rewrite AWK-PROGRAM: main.conf through awk, written back in place so the
# file keeps its owner, mode and SELinux label.
rewrite() {
  local tmp
  tmp=$(mktemp)
  if ! awk -v marker="$marker" -v tag="$tag" "$1" "$target" > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  cat -- "$tmp" > "$target"
  rm -f -- "$tmp"
}

managed() { [[ -e $target ]] && grep -qxF -- "$marker" "$target"; }

case "$action" in
  off)
    remove_stale_drop
    if [[ ! -e $target ]]; then
      # Writing one would make the file the package installs later a
      # conflict, so BlueZ has to be there first.
      printf 'No %s: BlueZ is not installed. Nothing changed.\n' "$target" >&2
      exit 1
    fi
    [[ -e $backup ]] || cp -a -- "$target" "$backup"
    # Our own lines from an earlier run go first (the marker and the line
    # after it), then any active AutoEnable in [Policy] is commented out and
    # ours goes right under the section's header - or a section is added.
    rewrite '
      skip { skip = 0; next }
      $0 == marker { skip = 1; next }
      /^[[:space:]]*\[/ {
        policy = ($0 ~ /^[[:space:]]*\[Policy\][[:space:]]*$/)
        print
        if (policy && !done) { print marker; print "AutoEnable=false"; done = 1 }
        next
      }
      policy && /^[[:space:]]*AutoEnable[[:space:]]*=/ { print tag $0; next }
      { print }
      END { if (!done) { print "[Policy]"; print marker; print "AutoEnable=false" } }'
    printf 'Set AutoEnable=false in %s - Bluetooth stays where you leave it.\n' "$target"
    printf 'It takes effect on the next boot (the file as it was: %s).\n' "$backup"
    ;;
  on)
    remove_stale_drop
    if managed || { [[ -e $target ]] && grep -q "^$tag" "$target"; }; then
      rewrite '
        skip { skip = 0; next }
        $0 == marker { skip = 1; next }
        index($0, tag) == 1 { print substr($0, length(tag) + 1); next }
        { print }'
      printf 'Took AutoEnable=false out of %s - BlueZ powers the adapter on at boot again.\n' "$target"
      # The copy has done its job once the file is the same again.
      if [[ -e $backup ]] && cmp -s -- "$backup" "$target"; then
        rm -f -- "$backup"
      fi
    else
      printf 'Nothing of this project in %s\n' "$target"
    fi
    ;;
  status)
    if managed; then
      printf 'installed: %s\n' "$target"
      grep -hE '^\s*AutoEnable' "$target" 2>/dev/null || true
    else
      printf 'absent: %s (BlueZ decides, and its default is on)\n' "$target"
    fi
    [[ -e $stale ]] && printf 'stale: %s (BlueZ does not read it; off or on removes it)\n' "$stale"
    true
    ;;
  *)
    printf 'Usage: %s off|on|status [--root DIR]\n' "$0" >&2
    exit 2
    ;;
esac
