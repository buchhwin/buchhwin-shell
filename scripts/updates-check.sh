#!/usr/bin/env bash
set -uo pipefail

# Read-only update check for Settings > Updates. Never installs, upgrades or
# removes anything and needs no root: dnf5 keeps a per-user metadata cache
# ($XDG_CACHE_HOME/libdnf5), checkupdates syncs a copy of pacman's database
# of its own, and flatpak remote-ls only reads the remotes.
#   updates-check.sh [--refresh] [--cache-only]
#     --refresh     force a metadata refresh (the shell passes it at most once
#                   per check interval); otherwise dnf refreshes only expired
#                   repositories
#     --cache-only  dnf uses cached metadata only (nested sessions; flatpak
#                   summaries are small and always read from the remote)
# Output: sections "@NAME EXIT" followed by the command's output, parsed by
# services/updates/UpdatesLogic.js:
#   @dnf              dnf5 check-upgrade --json (stderr in @dnf-stderr); on
#                     openSUSE zypper's list in the same JSON (zypper-updates.py),
#                     on Arch checkupdates and the AUR's (pacman-updates.py)
#   @dnf-cached       the same from the cache when the online run failed
#   @advisories       dnf5 advisory list --json (cache only, after @dnf)
#   @installed        rpm NAME.ARCH<TAB>EPOCH:VERSION-RELEASE of the upgrades
#                     (on Arch the old versions checkupdates names)
#   @flatpak-system / @flatpak-user   remote-ls --updates (+ -stderr, -cached)
#   @flatpak-installed                flatpak list with the installation
#   @end
refresh=0
cache_only=0
for arg in "$@"; do
  case $arg in
    --refresh) refresh=1 ;;
    --cache-only) cache_only=1 ;;
    *) printf 'usage: %s [--refresh] [--cache-only]\n' "$0" >&2; exit 2 ;;
  esac
done

tmp=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-updates.XXXXXX") || exit 1
trap 'rm -rf -- "$tmp"' EXIT

# section NAME TIMEOUT COMMAND...: runs the command and prints its stdout (and
# a non-empty stderr as NAME-stderr).
section() {
  local name=$1 limit=$2 code
  shift 2
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '@%s 127\n' "$name"
    return 127
  fi
  LC_ALL=C.UTF-8 timeout "$limit" "$@" >"$tmp/out" 2>"$tmp/err" </dev/null
  code=$?
  printf '@%s %d\n' "$name" "$code"
  cat -- "$tmp/out"
  if [[ -s $tmp/err ]]; then
    printf '\n@%s-stderr %d\n' "$name" "$code"
    tail -n 20 -- "$tmp/err"
  fi
  printf '\n'
  return "$code"
}

# openSUSE: zypper as a user never refreshes (that needs root and is the
# system's own timer's job), it reads the cache - so --refresh and
# --cache-only change nothing there. Its XML becomes dnf5's JSON under the
# same section name, and everything below, the installed versions included,
# stays one path for both distributions.
zypper_updates() {
  local code
  LC_ALL=C.UTF-8 timeout 300 zypper --non-interactive --no-refresh --xmlout list-updates \
    >"$tmp/zypper.xml" 2>"$tmp/err" </dev/null
  code=$?
  if (( code == 0 )) && ! python3 "${BASH_SOURCE[0]%/*}/zypper-updates.py" <"$tmp/zypper.xml" >"$tmp/out" 2>>"$tmp/err"; then
    code=1
  fi
  printf '@dnf %d\n' "$code"
  (( code == 0 )) && cat -- "$tmp/out"
  if [[ -s $tmp/err ]]; then
    printf '\n@dnf-stderr %d\n' "$code"
    tail -n 20 -- "$tmp/err"
  fi
  printf '\n'
  return "$code"
}

# Arch: checkupdates syncs its own copy of pacman's database (no root, the
# system's database untouched) and lists "name old -> new"; exit 2 means
# nothing to update. An AUR helper's -Qua adds the AUR's, which pacman does not
# know about. Both become dnf5's JSON and the @installed lines, so nothing
# below this branch knows it ran on Arch. --cache-only reads the copy as it
# is; --refresh changes nothing, checkupdates always syncs otherwise.
pacman_converter=${BASH_SOURCE[0]%/*}/pacman-updates.py
# pacman_json DB: $tmp/pacman.txt and $tmp/aur.txt as dnf5's JSON in
# $tmp/out, each package's repository read from the synced copy DB.
pacman_json() {
  LC_ALL=C pacman -Sl --dbpath "$1" >"$tmp/repos.txt" 2>/dev/null || : >"$tmp/repos.txt"
  python3 "$pacman_converter" json "$tmp/repos.txt" "$tmp/pacman.txt" "$tmp/aur.txt" >"$tmp/out" 2>>"$tmp/err"
}
pacman_installed() {
  printf '@installed 0\n'
  python3 "$pacman_converter" installed "$tmp/pacman.txt" "$tmp/aur.txt" 2>/dev/null
  printf '\n'
}
pacman_updates() {
  local code cached db=${CHECKUPDATES_DB:-${XDG_CACHE_HOME:-$HOME/.cache}/buchhwin-shell/checkup-db}
  local helper="" args=(--nocolor)
  if ! command -v checkupdates >/dev/null 2>&1; then
    printf '@dnf 127\n\n@dnf-stderr 127\ncheckupdates is not installed (package pacman-contrib)\n\n'
    return 127
  fi
  mkdir -p -- "$db"
  (( cache_only )) && args+=(--nosync)
  CHECKUPDATES_DB=$db LC_ALL=C.UTF-8 timeout 300 checkupdates "${args[@]}" \
    >"$tmp/pacman.txt" 2>"$tmp/err" </dev/null
  code=$?
  (( code == 2 )) && code=0
  : >"$tmp/aur.txt"
  for candidate in paru yay; do
    command -v "$candidate" >/dev/null 2>&1 && { helper=$candidate; break; }
  done
  # Not in nested sessions (they never reach the network): the AUR is asked
  # over the internet every time.
  if (( code == 0 && !cache_only )) && [[ -n $helper ]]; then
    # Exits 1 when the AUR has nothing newer; only the lines count.
    LC_ALL=C.UTF-8 timeout 120 "$helper" -Qua --color=never >"$tmp/aur.txt" 2>/dev/null </dev/null || true
  fi
  if (( code == 0 )); then
    pacman_json "$db" || code=1
  fi
  printf '@dnf %d\n' "$code"
  (( code == 0 )) && cat -- "$tmp/out"
  if [[ -s $tmp/err ]]; then
    printf '\n@dnf-stderr %d\n' "$code"
    tail -n 20 -- "$tmp/err"
  fi
  printf '\n'
  if (( code == 0 )); then
    pacman_installed
  elif (( !cache_only )) && [[ -d $db/sync ]]; then
    # Offline (checkupdates then only says "Cannot fetch updates") or a broken
    # mirror: the copy the last successful sync left behind still knows what
    # was pending then - the cached list, as dnf's cache is on Fedora. Without
    # the AUR, which is only ever asked online; not before a first sync.
    : >"$tmp/aur.txt"
    CHECKUPDATES_DB=$db LC_ALL=C.UTF-8 timeout 60 checkupdates --nocolor --nosync \
      >"$tmp/pacman.txt" 2>/dev/null </dev/null
    cached=$?
    (( cached == 2 )) && cached=0
    if (( cached == 0 )); then pacman_json "$db" || cached=1; fi
    printf '@dnf-cached %d\n' "$cached"
    (( cached == 0 )) && cat -- "$tmp/out"
    printf '\n'
    (( cached == 0 )) && pacman_installed
  fi
  return "$code"
}

# Arch, or a derivative of it, by its os-release - not by which package
# managers happen to be on PATH: Arch's extra packages dnf5 and zypper too,
# and with either installed the check asked a package manager that manages
# nothing here. BUCHHWIN_OS_RELEASE
# points at another file (tests), as in install/lib/distro.sh; then the
# machine's /etc/arch-release does not count either.
os_release_arch() {
  local file=${BUCHHWIN_OS_RELEASE:-/etc/os-release} ids=""
  if [[ -r $file ]]; then
    # shellcheck disable=SC1090
    ids=$(. "$file" 2>/dev/null; printf '%s %s' "${ID:-}" "${ID_LIKE:-}") || ids=""
  fi
  [[ " $ids " == *" arch "* ]] && return 0
  [[ -z ${BUCHHWIN_OS_RELEASE:-} && -e /etc/arch-release ]]
}

names=$tmp/names
zypper_only=0
pacman_only=0
if os_release_arch; then
  pacman_only=1
elif ! command -v dnf5 >/dev/null 2>&1 && ! command -v zypper >/dev/null 2>&1 \
    && command -v pacman >/dev/null 2>&1; then
  pacman_only=1
else
  command -v dnf5 >/dev/null 2>&1 || ! command -v zypper >/dev/null 2>&1 || zypper_only=1
fi
if (( pacman_only )); then
  pacman_updates
elif (( zypper_only )); then
  zypper_updates
  (( $? == 0 )) && cp -- "$tmp/out" "$tmp/dnf.json"
else
  dnf_args=(check-upgrade --json)
  (( cache_only )) && dnf_args+=(--cacheonly)
  (( refresh && !cache_only )) && dnf_args+=(--refresh)
  section dnf 600 dnf5 "${dnf_args[@]}"
  code=$?
  if (( code == 0 || code == 100 )); then
    cp -- "$tmp/out" "$tmp/dnf.json"
  elif (( code != 127 && !cache_only )); then
    # Offline or a broken mirror: show what the cache knows.
    section dnf-cached 120 dnf5 check-upgrade --json --cacheonly
    code=$?
    (( code == 0 || code == 100 )) && cp -- "$tmp/out" "$tmp/dnf.json"
  fi
fi
if [[ -s $tmp/dnf.json ]]; then
  # zypper's patches are not mapped to packages, so openSUSE has no advisories.
  (( zypper_only )) || section advisories 120 dnf5 advisory list --json --cacheonly
  # Installed versions of the packages that have upgrades.
  if command -v jq >/dev/null 2>&1; then
    jq -r '.upgrades[]? | "\(.name).\(.arch)"' "$tmp/dnf.json" 2>/dev/null | sort -u >"$names"
    printf '@installed 0\n'
    if [[ -s $names ]]; then
      rpm -qa --qf '%{NAME}.%{ARCH}\t%{EPOCH}:%{VERSION}-%{RELEASE}\n' 2>/dev/null \
        | awk -F '\t' 'NR == FNR { want[$1] = 1; next } ($1 in want)' "$names" -
    fi
    printf '\n'
  fi
fi

flatpak_columns=--columns=application,name,version,branch,origin,ref
for installation in system user; do
  flatpak_args=(remote-ls "--$installation" --updates "$flatpak_columns")
  section "flatpak-$installation" 120 flatpak "${flatpak_args[@]}"
  code=$?
  if (( code != 0 && code != 127 )); then
    section "flatpak-$installation-cached" 60 flatpak "${flatpak_args[@]}" --cached
  fi
done
section flatpak-installed 60 flatpak list --columns=application,branch,version,installation
printf '@end 0\n'
