#!/usr/bin/env bash
set -euo pipefail

# Optional, system-wide: tell systemd-logind to leave the lid switch alone, so
# the shell is the only thing that decides what closing the lid does. Called by
# install/system-install.sh --logind-lid / --logind-lid-remove.
#
#   logind-lid.sh install|remove|status [--root DIR]
#
# **Why this exists, in one boot's journal.** The machine had
# `HandleLidSwitch=suspend` and `HandleLidSwitchExternalPower=suspend` in a
# hand-written drop-in of the same name, and logind re-reads the lid whenever a
# session appears. Logging in with the lid shut therefore went:
#
#   10:31:46  New session '2' of user 'buchhwin'
#   10:31:47  systemd-logind: Suspending...
#   10:31:48  session-2.scope: Unit now frozen-by-parent
#   10:32:11  Lid opened  -> resume, amdgpu DMCUB error
#   10:32:13  the session finally reaches its targets
#
# One second into starting, the whole session is frozen for as long as the lid
# stays shut, and it thaws onto a GPU that has just come back. Everything that
# was starting in that second - the compositor, the shell, autostarted apps -
# comes up half initialised, which is what "after a restart there are so many
# bugs" was. The shell's own `systemd-inhibit` cannot help: it does not exist
# yet at 10:31:47.
#
# So logind hands the lid over entirely. `IdleService.lidClosed()` handles all
# four settings itself, suspend included, and reads the lid at startup because
# a switch is an edge and a session that begins shut never sees one.
#
# The file is only written when it is this project's - a drop-in of the same
# name that says something else is backed up beside it first. `remove` puts the
# backup back, or deletes the file when there was none.
#
# --root DIR works below DIR without root rights (tests).

drop_dir=/etc/systemd/logind.conf.d
drop_name=50-buchhwin.conf
marker='# Managed by buchhwin-shell (install/logind-lid.sh)'

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
backup="$target.before-buchhwin"

write_drop() {
  install -d -- "$(dirname -- "$target")"
  cat > "$target" <<CONF
$marker
#
# The shell decides what the lid does (Settings > Power > Lid), including
# suspend. logind must not act on it at all: it re-reads the lid when a session
# appears, and a login with the lid shut would suspend the machine one second
# into starting the session - before the shell exists to inhibit anything.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
CONF
  chmod 0644 -- "$target"
}

case "$action" in
  install)
    if [[ -e $target ]] && ! grep -qF "$marker" "$target"; then
      # The backup is the file that was there before this project ever wrote
      # the drop-in, and `remove` puts exactly that back. A foreign file found
      # a second time - somebody replaced ours in between - must not overwrite
      # it, so that one is kept beside it under its own name.
      if [[ -e $backup ]]; then
        aside="$backup-$(date +%Y%m%d%H%M%S)"
        cp -a -- "$target" "$aside"
        printf 'Kept the existing drop-in as %s (%s is the original and stays)\n' "$aside" "$backup"
      else
        cp -a -- "$target" "$backup"
        printf 'Kept the existing drop-in as %s\n' "$backup"
      fi
    fi
    write_drop
    printf 'Wrote %s - logind leaves the lid to the shell.\n' "$target"
    printf 'It takes effect on the next boot (or: systemctl restart systemd-logind,\n'
    printf 'which ends every login session on this machine).\n'
    ;;
  remove)
    if [[ -e $backup ]]; then
      mv -- "$backup" "$target"
      printf 'Put %s back.\n' "$target"
    elif [[ -e $target ]] && grep -qF "$marker" "$target"; then
      rm -f -- "$target"
      printf 'Removed %s - logind handles the lid again.\n' "$target"
    else
      printf 'Nothing of this project to remove at %s\n' "$target"
    fi
    ;;
  status)
    if [[ ! -e $target ]]; then
      printf 'absent: %s\n' "$target"
    elif grep -qF "$marker" "$target"; then
      printf 'installed: %s\n' "$target"
    else
      printf 'foreign: %s exists and is not this project.\n' "$target"
    fi
    grep -hE '^\s*HandleLidSwitch' "$target" 2>/dev/null || true
    ;;
  *)
    printf 'Usage: %s install|remove|status [--root DIR]\n' "$0" >&2
    exit 2
    ;;
esac
