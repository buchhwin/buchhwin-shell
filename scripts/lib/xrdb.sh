# shellcheck shell=bash
# One writer at a time for the X resource database. `xrdb -merge` reads the
# RESOURCE_MANAGER property, adds its lines and writes the whole property back,
# so two merges started in the same moment - the cursor's and the DPI's, both
# detached by the shell - can each write back a copy without the other's keys.
# That is how the cursor came up as breeze_cursors 24 beside an Xft.dpi of
# 144. Source this file and call xrdb_merge with the lines to merge.
xrdb_merge() {
  local lock=${XDG_RUNTIME_DIR:-/tmp}/buchhwin-shell-xrdb.lock
  if command -v flock >/dev/null 2>&1; then
    printf '%s\n' "$@" | flock -w 5 "$lock" xrdb -merge - 2>/dev/null || true
  else
    printf '%s\n' "$@" | xrdb -merge - 2>/dev/null || true
  fi
}
