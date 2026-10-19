#!/usr/bin/env bash
set -euo pipefail

# scripts/lib/quickshell-dirs.sh against a runtime directory of its own: the
# directory of an instance that is gone goes, with its links; one whose lock
# a process holds stays however old it is, and so does a recent one. Links a
# stopped sweep left go later, and so do a configuration's own directories
# once the last of its instances has gone.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-qsdirs.XXXXXX")
holder=""
cleanup() { if [[ -n $holder ]]; then kill "$holder" 2>/dev/null || true; fi; rm -rf -- "$sandbox"; }
trap cleanup EXIT
failures=0
check() {
  if eval "$2"; then :; else printf 'FAIL quickshell-dirs: %s\n' "$1"; failures=$((failures + 1)); fi
}

root="$sandbox/run/quickshell"
mkdir -p "$root/by-id" "$root/by-pid" "$root/by-shell/aaaa" "$root/by-path"
# instance DIR-ID PID AGE: a directory as Quickshell leaves it, AGE ago.
instance() {
  mkdir -p "$root/by-id/$1"
  : > "$root/by-id/$1/instance.lock"; : > "$root/by-id/$1/log.qslog"
  ln -s "$root/by-id/$1" "$root/by-pid/$2"
  ln -s "$root/by-id/$1" "$root/by-shell/aaaa/$1"
  touch -d "$3" "$root/by-id/$1/instance.lock" "$root/by-id/$1/log.qslog" "$root/by-id/$1"
}
instance live1nt 101 '3 hours ago'
instance gone1nt 102 '2 hours ago'
instance fresh1nt 103 '5 minutes ago'
ln -s "$root/by-shell/aaaa" "$root/by-path/bbbb"
# The live one's lock is held as Quickshell holds it: a POSIX lock, by a
# process that lives until the test ends it.
python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "r+"); fcntl.lockf(f, fcntl.LOCK_EX); print("locked", flush=True); time.sleep(60)' \
  "$root/by-id/live1nt/instance.lock" > "$sandbox/holder.out" &
holder=$!
for _ in {1..50}; do [[ -s $sandbox/holder.out ]] && break; sleep 0.1; done
check 'the stand-in holds its lock' '[[ -s $sandbox/holder.out ]]'

# shellcheck source=../scripts/lib/quickshell-dirs.sh
source "$project_dir/scripts/lib/quickshell-dirs.sh"
XDG_RUNTIME_DIR="$sandbox/run" quickshell_sweep_dirs 60
check 'a gone instance older than an hour is removed' '[[ ! -e $root/by-id/gone1nt ]]'
check 'and its links' '[[ ! -L $root/by-pid/102 && ! -L $root/by-shell/aaaa/gone1nt ]]'
check 'a running instance stays, however old' '[[ -d $root/by-id/live1nt && -L $root/by-pid/101 && -L $root/by-shell/aaaa/live1nt ]]'
check 'a recent one stays (a crashed shell'"'"'s log, read after the restart)' '[[ -d $root/by-id/fresh1nt && -L $root/by-pid/103 ]]'
check 'the path link to a shell stays' '[[ -L $root/by-path/bbbb ]]'
XDG_RUNTIME_DIR="$sandbox/run" quickshell_sweep_dirs 1
check 'with a shorter age, the recent gone one goes too' '[[ ! -e $root/by-id/fresh1nt && -d $root/by-id/live1nt ]]'
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true; holder=""
XDG_RUNTIME_DIR="$sandbox/run" quickshell_sweep_dirs 60
check 'and once its process is gone, the old live one too' '[[ ! -e $root/by-id/live1nt && ! -L $root/by-pid/101 ]]'
# A sweep that was stopped half-way left links to directories it had
# removed; a later one that removes nothing takes them all the same.
ln -s "$root/by-id/stopped1nt" "$root/by-pid/104"
ln -s "$root/by-id/stopped1nt" "$root/by-shell/aaaa/stopped1nt"
XDG_RUNTIME_DIR="$sandbox/run" quickshell_sweep_dirs 60
check 'dangling links go without a directory to remove' '[[ ! -L $root/by-pid/104 && ! -L $root/by-shell/aaaa/stopped1nt ]]'
# The configuration's own directories, once its last instance has gone: an
# empty by-shell directory unchanged for an hour goes, with the path link to
# it and its vfs folder; a recent one stays, so does one with a link in it,
# and a vfs folder whose tooling lock a running shell holds.
mkdir -p "$root/by-shell/cccc" "$root/by-shell/dddd" "$root/by-shell/eeee" "$root/vfs/cccc" "$root/vfs/dddd" "$root/vfs/ffff"
: > "$root/vfs/cccc/tooling.lock"; : > "$root/vfs/dddd/tooling.lock"; : > "$root/vfs/ffff/tooling.lock"
ln -s "$root/by-shell/cccc" "$root/by-path/cccc"; ln -s "$root/by-shell/dddd" "$root/by-path/dddd"
instance live2nt 105 '3 hours ago'
ln -s "$root/by-id/live2nt" "$root/by-shell/eeee/live2nt"
touch -d '2 hours ago' "$root/by-shell/cccc" "$root/by-shell/eeee" "$root/vfs/cccc" "$root/vfs/dddd" "$root/vfs/ffff"
python3 -c 'import fcntl, sys, time
a = open(sys.argv[1], "r+"); fcntl.lockf(a, fcntl.LOCK_EX)
b = open(sys.argv[2], "r+"); fcntl.lockf(b, fcntl.LOCK_EX); print("locked", flush=True); time.sleep(60)' \
  "$root/by-id/live2nt/instance.lock" "$root/vfs/ffff/tooling.lock" > "$sandbox/holder2.out" &
holder=$!
for _ in {1..50}; do [[ -s $sandbox/holder2.out ]] && break; sleep 0.1; done
check 'the second stand-in holds its locks' '[[ -s $sandbox/holder2.out ]]'
XDG_RUNTIME_DIR="$sandbox/run" quickshell_sweep_dirs 60
check 'an empty by-shell directory unchanged for an hour goes, with its path link and vfs folder' \
  '[[ ! -e $root/by-shell/cccc && ! -L $root/by-path/cccc && ! -e $root/vfs/cccc ]]'
check 'a recent empty one stays, with its path link and vfs folder' \
  '[[ -d $root/by-shell/dddd && -L $root/by-path/dddd && -d $root/vfs/dddd ]]'
check 'one with a link to a running instance stays' '[[ -L $root/by-shell/eeee/live2nt && -d $root/by-id/live2nt ]]'
check 'a vfs folder whose tooling lock is held stays' '[[ -f $root/vfs/ffff/tooling.lock ]]'
# A caller that stopped a shell of its own removes that instance at once,
# but never one that still runs.
instance done1nt 106 '1 minute ago'
quickshell_remove_instance_in() { XDG_RUNTIME_DIR="$sandbox/run" quickshell_remove_instance "$1"; }
quickshell_remove_instance_in done1nt
check 'a stopped instance is removed at once, with its links' \
  '[[ ! -e $root/by-id/done1nt && ! -L $root/by-pid/106 && ! -L $root/by-shell/aaaa/done1nt ]]'
quickshell_remove_instance_in live2nt
check 'a running one is not' '[[ -d $root/by-id/live2nt && -L $root/by-pid/105 ]]'
quickshell_remove_instance_in '../by-pid'
quickshell_remove_instance_in ''
check 'nor anything that is not an instance id' '[[ -d $root/by-pid ]]'
kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true; holder=""
# Nothing to do, or no runtime directory: nothing happens, and no failure.
XDG_RUNTIME_DIR="$sandbox/nowhere" quickshell_sweep_dirs 60
check 'a missing runtime directory is no failure' 'true'
( unset XDG_RUNTIME_DIR; quickshell_sweep_dirs 60 )
check 'nor is none at all' 'true'

if (( failures )); then
  printf 'TESTS FAILED quickshell-dirs (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED quickshell-dirs\n'
