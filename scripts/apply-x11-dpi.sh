#!/usr/bin/env bash
set -euo pipefail

# Tell X11 clients the scale the screen really runs at, or stop telling them.
#
# With Settings > Displays > "Sharp X11 applications" on, XWayland draws in
# real pixels and reports its screen as 96 DPI, so on a display at 1.5 every
# X11 window comes up a third smaller. `Xft.dpi` in the X resource database is
# the one scale that reaches X11 clients and nothing else: GTK, Qt and Java on
# X11 read it, and a Wayland client never sees the X server. The environment
# variables that would do the same job (GDK_SCALE, QT_SCALE_FACTOR) reach
# Wayland clients too, which are already scaled and would double - that is why
# they are not used, and why the shell writes a resource rather than an env.
#
#   apply-x11-dpi.sh 144     Xft.dpi: 144 (a screen at 1.5)
#   apply-x11-dpi.sh reset   Xft.dpi: 96, which is what X11 assumes anyway
#
# Only applications started afterwards read it - the same rule as the
# compositor option it accompanies. It writes the host's resource database, so
# like apply-cursor-env.sh it refuses to run in a nested test session - one
# recognised by its files (scripts/lib/nested-guard.sh), not only by the flag.
#
# A reset writes 96 rather than removing the key. Removing it meant reloading
# a snapshot of the database without it, and the cursor script merges its own
# two keys into the same database at the same moment - the snapshot put the
# old cursor back on top of them. Every writer is a merge now, and the merges
# take turns through the lock in lib/xrdb.sh.
# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"
if nested_environment; then
  printf 'apply-x11-dpi: skipped in a nested test session\n' >&2
  exit 0
fi
want=${1:?dpi or reset}
[[ $want == reset || $want =~ ^[0-9]{2,3}$ ]] || { printf 'invalid dpi: %s\n' "$want" >&2; exit 2; }
if [[ -z ${DISPLAY:-} ]] || ! command -v xrdb >/dev/null 2>&1; then
  exit 0
fi
# shellcheck source=lib/xrdb.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/xrdb.sh"
[[ $want == reset ]] && want=96
xrdb_merge "Xft.dpi: $want"
