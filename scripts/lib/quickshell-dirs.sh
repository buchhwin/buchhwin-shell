# shellcheck shell=bash
# Quickshell keeps a directory for every instance it starts in
# $XDG_RUNTIME_DIR/quickshell/by-id - its detailed log, its lock and its IPC
# socket - with links to it in by-pid and by-shell, and nothing removes one
# once its instance is gone. Every restart, every test and every nested run
# left one: 800 of them, 37 MB of the runtime directory's tmpfs (memory)
# after one day. Each configuration path also gets a by-shell directory for
# those links, a by-path link to that directory and a vfs folder (its
# tooling lock), and those stay too once the last instance has gone. Source
# this file.

# The inodes of the locks held right now, as " 1 2 3 ": /proc/locks names
# each lock's device and inode (MAJ:MIN in hex, the inode in decimal):
# `1: POSIX ADVISORY WRITE 52233 00:3f:3939 0 EOF`. Fails without /proc/locks.
quickshell_held_inodes() {
  local locks
  locks=$(cat /proc/locks 2>/dev/null) || return 1
  printf ' %s ' "$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9a-f]+:[0-9a-f]+:[0-9]+$/) { split($i, f, ":"); printf "%s ", f[3]; break } }' <<<"$locks")"
}

# quickshell_sweep_dirs [MINUTES]: removes the directories of instances that
# are gone and that have not changed for MINUTES (default 60), and the links
# to them. An instance holds a POSIX lock on its instance.lock for as long as
# it runs; a directory whose lock is held stays, and so does a newer one (a
# crashed shell's log, read after the restart; an instance that has not
# taken its lock yet). Without /proc/locks nothing is removed.
#
# A by-shell directory goes once it is empty and has not changed for MINUTES
# (its last link went that long ago), with the path link to it and its vfs
# folder, unless a running shell holds that folder's tooling lock. Quickshell
# makes a by-shell directory and then the link in it, so a shell of that
# configuration starting at the same moment would find its directory gone;
# a caller that starts a shell sweeps once that shell is listed
# (scripts/start-shell.sh), and the directory of a configuration that has
# not run for an hour is the only one this can touch.
quickshell_sweep_dirs() {
  local minutes=${1:-60} root=${XDG_RUNTIME_DIR:-}/quickshell held dir inode link id
  [[ -n ${XDG_RUNTIME_DIR:-} && -d $root/by-id && $minutes =~ ^[0-9]+$ ]] || return 0
  held=$(quickshell_held_inodes) || return 0
  while IFS= read -r dir; do
    [[ ${dir##*/} =~ ^[a-z0-9]+$ && -f $dir/instance.lock ]] || continue
    inode=$(stat -c %i -- "$dir/instance.lock" 2>/dev/null) || continue
    [[ $held == *" $inode "* ]] && continue
    rm -rf -- "$dir"
  done < <(find "$root/by-id" -mindepth 1 -maxdepth 1 -type d -not -newermt "$minutes minutes ago" 2>/dev/null)
  # The links that point at nothing any more: those of the directories just
  # removed, and any a sweep left when it was stopped half-way (a nested
  # session's stop ends the start that runs it) - every time, not only after
  # a removal, or those stay for good.
  for link in "$root"/by-pid/* "$root"/by-shell/*/*; do
    if [[ -L $link && ! -e $link ]]; then rm -f -- "$link"; fi
  done
  # Empty and unchanged for MINUTES; -delete removes a directory only while
  # it is empty, so one that got a link meanwhile stays.
  if [[ -d $root/by-shell ]]; then
    find "$root/by-shell" -mindepth 1 -maxdepth 1 -type d -regex '.*/[a-z0-9]+' -empty \
      -not -newermt "$minutes minutes ago" -delete 2>/dev/null || true
  fi
  if [[ -d $root/vfs ]]; then
    while IFS= read -r dir; do
      id=${dir##*/}
      [[ $id =~ ^[a-z0-9]+$ && ! -e $root/by-shell/$id ]] || continue
      if [[ -e $dir/tooling.lock ]]; then
        inode=$(stat -c %i -- "$dir/tooling.lock" 2>/dev/null) || continue
        [[ $held == *" $inode "* ]] && continue
      fi
      rm -rf -- "$dir"
    done < <(find "$root/vfs" -mindepth 1 -maxdepth 1 -type d -not -newermt "$minutes minutes ago" 2>/dev/null)
  fi
  for link in "$root"/by-path/*; do
    if [[ -L $link && ! -e $link ]]; then rm -f -- "$link"; fi
  done
  return 0
}

# quickshell_remove_instance ID: removes the directory of the instance ID and
# the links to it at once, for a caller that has just stopped a shell of its
# own (the nested smoke test's) - only once its lock is no longer held, so
# never a running one's. The by-shell directory stays for the sweep.
quickshell_remove_instance() {
  local id=${1:-} root=${XDG_RUNTIME_DIR:-}/quickshell held inode link
  [[ -n ${XDG_RUNTIME_DIR:-} && $id =~ ^[a-z0-9]+$ && -f $root/by-id/$id/instance.lock ]] || return 0
  held=$(quickshell_held_inodes) || return 0
  inode=$(stat -c %i -- "$root/by-id/$id/instance.lock" 2>/dev/null) || return 0
  [[ $held == *" $inode "* ]] && return 0
  rm -rf -- "$root/by-id/$id"
  for link in "$root"/by-pid/* "$root"/by-shell/*/"$id"; do
    if [[ -L $link && ! -e $link ]]; then rm -f -- "$link"; fi
  done
  return 0
}
