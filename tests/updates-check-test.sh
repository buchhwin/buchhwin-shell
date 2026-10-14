#!/usr/bin/env bash
set -euo pipefail
# scripts/updates-check.sh on Arch, against stub checkupdates, paru, pacman,
# flatpak, dnf5 and zypper on a PATH that reaches nothing else: no update
# check here may ask a real mirror, the AUR or a Flatpak remote. Covered:
# checkupdates' exit 2 (nothing to update), a list turned into dnf5's JSON
# and the @installed lines, the AUR beside it and skipped with --cache-only,
# a missing checkupdates naming itself, the cached list when the sync fails,
# and the choice of the package manager by os-release rather than by what
# happens to be installed (Arch's extra packages dnf5 and zypper too).
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
script="$project_dir/scripts/updates-check.sh"
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-updatestest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL updates-check: %s\n' "$2"; failures=$((failures + 1)); fi; }

bin="$sandbox/bin"; calls="$sandbox/calls.log"
mkdir -p "$bin" "$sandbox/home" "$sandbox/cache" "$sandbox/run"
# The real tools the script itself needs, and nothing else from this machine.
for tool in mktemp rm timeout cat tail python3 mkdir cp sort awk jq; do
  real=$(command -v "$tool" 2>/dev/null) || continue
  ln -s "$real" "$bin/$tool"
done
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# checkupdates: STUB_OUT/STUB_EXIT (and STUB_ERR on stderr) for a sync,
# STUB_NOSYNC_OUT/STUB_NOSYNC_EXIT for --nosync, falling back to the former.
# It also records the database it was pointed at.
stub checkupdates 'printf "db=%s\n" "$CHECKUPDATES_DB" >> "$CALLS"
case " $* " in
  *" --nosync "*) out=${STUB_NOSYNC_OUT-$STUB_OUT}; code=${STUB_NOSYNC_EXIT:-${STUB_EXIT:-0}} ;;
  *) out=$STUB_OUT; code=${STUB_EXIT:-0}; [ -z "$STUB_ERR" ] || printf "%s\n" "$STUB_ERR" >&2 ;;
esac
[ -z "$out" ] || printf "%s\n" "$out"
exit "$code"'
stub paru '[ -n "$STUB_AUR" ] || exit 1; printf "%s\n" "$STUB_AUR"'
stub pacman 'case "$*" in -Sl*) printf "core linux 6.17.1.arch1-1\nextra firefox 144.0-1\n" ;; esac'
stub flatpak
stub dnf5 'case "$*" in check-upgrade*) printf "{\"upgrades\": []}\n" ;; advisory*) printf "[]\n" ;; esac'
stub zypper
stub rpm
export CALLS="$calls"
if [[ $(PATH="$bin" command -v checkupdates) != "$bin/checkupdates" || $(PATH="$bin" command -v flatpak) != "$bin/flatpak" ]]; then
  printf 'updates-check test: the stubs are not what PATH finds, refusing to run\n' >&2
  exit 1
fi

printf 'NAME="Arch Linux"\nID=arch\n' > "$sandbox/os-arch"
printf 'ID=endeavouros\nID_LIKE=arch\n' > "$sandbox/os-derivative"
printf 'ID=fedora\nVERSION_ID=44\n' > "$sandbox/os-fedora"
db="$sandbox/cache/buchhwin-shell/checkup-db"
machine=$(uname -m)
tab=$'\t'

stubs() { export STUB_OUT=${1:-} STUB_EXIT=${2:-0} STUB_ERR=${3:-} STUB_AUR=${4:-}; unset STUB_NOSYNC_OUT STUB_NOSYNC_EXIT; }
# run OS-RELEASE [ARGS...]: the whole check in the sandbox; $out, $status.
run() {
  local os_release=$1; shift
  : > "$calls"
  out=$(env -u CHECKUPDATES_DB -u XDG_CONFIG_HOME PATH="$bin" HOME="$sandbox/home" \
    XDG_CACHE_HOME="$sandbox/cache" XDG_RUNTIME_DIR="$sandbox/run" BUCHHWIN_OS_RELEASE="$os_release" \
    "$BASH" "$script" "$@" 2>"$sandbox/stderr.log") && status=0 || status=$?
}
# sec NAME: the body of section @NAME.
sec() { awk -v s="@$1 " 'index($0, s) == 1 { p = 1; next } /^@/ { p = 0 } p && NF' <<<"$out"; }
has() { grep -qx -- "$1" <<<"$out"; }

# ---- nothing to update (checkupdates exits 2) ---------------------------------
stubs "" 2
run "$sandbox/os-arch"
check '[[ $status -eq 0 ]] && has "@dnf 0" && [[ $(sec dnf) == "{\"upgrades\": []}" ]]' \
  "exit 2 is no updates, not a failure (got: $(sec dnf | head -1))"
check 'has "@installed 0" && [[ -z $(sec installed) ]] && has "@end 0"' "an empty @installed, and the report ends"
check 'grep -qx "db=$db" "$calls"' "checkupdates syncs the shell's own copy of the database ($(grep "^db=" "$calls"))"
check '! grep -q "^checkupdates .*--nosync" "$calls"' "and a normal check syncs it"

# ---- a list, with the AUR beside it ------------------------------------------
stubs "linux 6.17.0.arch1-1 -> 6.17.1.arch1-1
icaclient 25.08-1 -> 26.04-1 [ignored]" 0 "" "brave-bin 1.97.1-1 -> 1.97.2-1"
run "$sandbox/os-arch"
json=$(sec dnf)
check '[[ $json == *"\"name\": \"linux\", \"arch\": \"$machine\", \"evr\": \"6.17.1.arch1-1\", \"repository\": \"core\""* ]]' \
  "the list becomes dnf5's JSON, with the repository from the synced copy ($json)"
check '[[ $json == *"\"name\": \"brave-bin\""*"\"repository\": \"aur\""* ]]' "the AUR's updates are in it, from aur"
check '[[ $json != *icaclient* ]]' "a package held back with IgnorePkg is not offered"
check 'grep -qx "linux.$machine${tab}6.17.0.arch1-1" <<<"$(sec installed)" && grep -qx "brave-bin.$machine${tab}1.97.1-1" <<<"$(sec installed)"' \
  "@installed names the old versions ($(sec installed | paste -sd' '))"
check 'grep -q "^paru -Qua" "$calls"' "the AUR helper is asked with -Qua"
check 'grep -q "^pacman -Sl --dbpath $db$" "$calls"' "the repositories are read from the copy, not the system's database"

# ---- --cache-only: the copy as it is, no AUR -----------------------------------
run "$sandbox/os-arch" --cache-only
check 'grep -q "^checkupdates .*--nosync" "$calls"' "--cache-only does not sync"
check '! grep -q "^paru" "$calls"' "and does not ask the AUR (nested sessions never reach the network)"
check 'has "@dnf 0" && [[ $(sec dnf) == *"\"name\": \"linux\""* ]]' "and still lists what the copy knows"

# ---- offline: the cached list ---------------------------------------------------
stubs "" 1 "==> ERROR: Cannot fetch updates"
export STUB_NOSYNC_OUT="linux 6.17.0.arch1-1 -> 6.17.1.arch1-1" STUB_NOSYNC_EXIT=0
rm -rf -- "$db"
run "$sandbox/os-arch"
check 'has "@dnf 1" && [[ $(sec dnf-stderr) == *"Cannot fetch updates"* ]]' "a failed sync is reported with checkupdates' reason"
check '! has "@dnf-cached 0" && ! grep -q "^checkupdates .*--nosync" "$calls"' "before a first sync there is no copy to fall back on"
mkdir -p "$db/sync"
run "$sandbox/os-arch"
check 'has "@dnf 1" && has "@dnf-cached 0" && [[ $(sec dnf-cached) == *"\"evr\": \"6.17.1.arch1-1\""* ]]' \
  "offline, the last synced copy's list comes as @dnf-cached ($(sec dnf-cached))"
check 'grep -qx "linux.$machine${tab}6.17.0.arch1-1" <<<"$(sec installed)"' "with its @installed lines"
check '! grep -q "^paru" "$calls"' "and without the AUR"
export STUB_NOSYNC_EXIT=1
run "$sandbox/os-arch"
check 'has "@dnf-cached 1" && ! has "@installed 0"' "a copy that cannot be read either is a failed @dnf-cached"
run "$sandbox/os-arch" --cache-only
check '[[ $(grep -c "^checkupdates" "$calls") -eq 1 ]] && ! has "@dnf-cached 0" && ! has "@dnf-cached 1"' \
  "--cache-only read the copy already; no second attempt"

# ---- checkupdates missing ------------------------------------------------------
stubs "" 2
mv "$bin/checkupdates" "$sandbox/checkupdates.away"
run "$sandbox/os-arch"
check 'has "@dnf 127" && [[ $(sec dnf-stderr) == "checkupdates is not installed (package pacman-contrib)" ]]' \
  "a missing checkupdates is 127 and names its package ($(sec dnf-stderr))"
check '[[ $status -eq 0 ]] && has "@end 0"' "and the rest of the report still runs"
mv "$sandbox/checkupdates.away" "$bin/checkupdates"

# ---- which package manager: os-release, not PATH --------------------------------
# dnf5 and zypper are on this PATH all along; Arch still asks checkupdates.
run "$sandbox/os-arch"
check 'grep -q "^checkupdates" "$calls" && ! grep -qE "^(dnf5|zypper) " "$calls"' \
  "Arch with dnf5 and zypper installed: checkupdates, never dnf5 or zypper"
run "$sandbox/os-derivative"
check 'grep -q "^checkupdates" "$calls" && ! grep -qE "^(dnf5|zypper) " "$calls"' "a derivative (ID_LIKE=arch) the same"
run "$sandbox/os-fedora"
check 'grep -q "^dnf5 check-upgrade --json" "$calls" && ! grep -q "^checkupdates" "$calls"' "Fedora asks dnf5"
check 'has "@dnf 0"' "and reports its section as before"

check '[[ ! -s $sandbox/stderr.log ]]' "nothing on stderr ($(head -c 200 "$sandbox/stderr.log"))"

if (( failures )); then printf 'TESTS FAILED updates-check (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED updates-check\n'
