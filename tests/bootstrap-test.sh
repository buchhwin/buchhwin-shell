#!/usr/bin/env bash
set -euo pipefail

# install/bootstrap.sh, against its dry run. The dry run is the whole test
# surface here on purpose: --apply installs packages, reaches the network and
# writes into $HOME, none of which belongs in a suite that has to be safe to
# run on the machine it is developed on.
#
# What is deliberately NOT tested: that every package name exists in the
# repositories (needs the network) and that the script refuses to run as root
# (`EUID` is readonly in bash and cannot be stubbed). The first is a manual
# check noted in docs/testing.md; the second is one `if` at the top of the file.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
script="$project_dir/install/bootstrap.sh"
failures=0

check() {
  if eval "$2"; then :; else printf 'FAIL bootstrap: %s\n' "$1"; failures=$((failures + 1)); fi
}

# The machine's own repositories must not decide what the dry run prints: a
# zypper that knows none stands in for the real one.
stub_bin=$(mktemp -d)
trap 'rm -rf -- "$stub_bin"' EXIT
printf '#!/bin/sh\nexit 1\n' >"$stub_bin/zypper"
chmod +x "$stub_bin/zypper"
export PATH="$stub_bin:$PATH"

# ---- the dry run, per distribution ----------------------------------------
# --distro rather than the machine's own os-release, so the suite checks both
# systems wherever it runs.
for distro in fedora opensuse-leap; do
  out=$("$script" --distro "$distro") || { printf 'FAIL bootstrap: the %s dry run exited non-zero\n' "$distro"; exit 1; }

  for step in \
    '1. What the package manager needs' '2. Repositories' '3. Packages' \
    '4. The fonts' '5. The shell itself' '6. The session entry' \
    '7. Default applications'; do
    check "$distro: the dry run names step '$step'" '[[ $out == *"$step"* ]]'
  done

  check "$distro: the dry run names the distribution" '[[ $out == *"Distribution: $distro"* ]]'
  check "$distro: the dry run says it changed nothing" '[[ $out == *"Nothing was changed"* ]]'
  check "$distro: the dry run runs nothing (no \"+ \" command lines)" '[[ $out != *$'"'"'\n  + '"'"'* ]]'

  # ---- the options -------------------------------------------------------
  minimal=$("$script" --distro "$distro" --minimal)
  check "$distro: --minimal leaves the extras out" '[[ $minimal != *wf-recorder* ]]'
  check "$distro: the default run has the extras" '[[ $out == *wf-recorder* ]]'
  check "$distro: --minimal leaves the applications out" '[[ $minimal != *brave-browser* ]]'
  check "$distro: the default run has the applications" '[[ $out == *brave-browser* ]]'
  check "$distro: --minimal says what it left out" '[[ $minimal == *"--minimal:"* ]]'

  skipped=$("$script" --distro "$distro" --skip-apps)
  check "$distro: --skip-apps leaves the applications out" '[[ $skipped != *brave-browser* ]]'
  check "$distro: --skip-apps keeps the extras" '[[ $skipped == *wf-recorder* ]]'

  # ---- the lists ---------------------------------------------------------
  # Through --list-packages rather than by parsing the package files: the
  # list has one owner, and the flag is what docs/testing.md tells people to
  # check against the repositories, so it is worth holding to account here.
  all_packages=$("$script" --distro "$distro" --list-packages)
  count=$(printf '%s\n' "$all_packages" | wc -l)
  unique=$(printf '%s\n' "$all_packages" | sort -u | wc -l)
  check "$distro: --list-packages lists something" '[[ $count -gt 20 ]]'
  check "$distro: no package is listed twice ($count listed, $unique distinct)" '[[ $count -eq $unique ]]'
  check "$distro: no package name has a stray character" \
    '! printf "%s\n" "$all_packages" | grep -qvE "^[A-Za-z0-9][A-Za-z0-9._+-]*$"'
  # The flag has to ignore the filters, or the check it exists for would
  # silently skip whatever the current options leave out.
  check "$distro: --list-packages ignores --minimal" \
    '[[ $("$script" --distro "$distro" --list-packages --minimal) == "$all_packages" ]]'
done

fedora=$("$script" --distro fedora)
leap=$("$script" --distro opensuse-leap)
check 'Fedora installs with dnf' '[[ $fedora == *"sudo dnf -y install"* && $fedora != *zypper* ]]'
check 'Fedora enables the Hyprland Copr' '[[ $fedora == *"copr enable sachesi/hyprland"* ]]'
check 'Leap installs with zypper' '[[ $leap == *"sudo zypper --non-interactive install --no-recommends"* && $leap != *"dnf "* ]]'
check 'Leap installs only from the repositories it names' \
  '[[ $leap == *"--repo repo-oss --repo quickshell-leap16 --repo brave-browser quickshell"* ]]'
check 'Leap adds the Quickshell repository below repo-oss' \
  '[[ $leap == *"--priority 120 https://download.opensuse.org/repositories/home:/AvengeMedia:"* ]]'
check 'Leap no longer adds the broken Hyprland repository' '[[ $leap != *"Cic17"* ]]'
check 'Leap fetches cliphist with a checksum (or has it already)' \
  '[[ $leap == *"download cliphist"*"sha256"* || $leap == *"cliphist is already installed"* ]]'
check 'Leap builds Hyprland, as a dry run in the dry run' \
  '[[ $leap == *"4b. Hyprland, built from source"*"Hyprland "*"v0.56.2"* && $leap != *"+ git clone"* ]]'
check 'Leap does not install Hyprland as a package' '! "$script" --distro opensuse-leap --list-packages | grep -qx hyprland'
check 'both Nerd Fonts are handled' '[[ $leap == *"FiraCode Nerd Font Propo"* && $leap == *"JetBrainsMono Nerd Font"* ]]'
check 'Fedora installs Hyprland as a package' '"$script" --distro fedora --list-packages | grep -qx hyprland'
check 'Fedora does not build anything' '[[ $fedora != *"built from source"* ]]'

# Detection from os-release, through the library the script uses.
lib="$project_dir/install/lib/distro.sh"
os_release=$(mktemp -d)
trap 'rm -rf -- "$os_release" "$stub_bin"' EXIT
detect() {
  printf '%s\n' "$1" >"$os_release/os-release"
  (unset BUCHHWIN_DISTRO; BUCHHWIN_OS_RELEASE="$os_release/os-release"; . "$lib"; distro_detect 2>/dev/null)
}
check 'Fedora is detected' '[[ $(detect "ID=fedora
VERSION_ID=44") == fedora ]]'
check 'Leap 16 is detected' '[[ $(detect "ID=\"opensuse-leap\"
VERSION_ID=\"16.0\"
PRETTY_NAME=\"openSUSE Leap 16.0\"") == opensuse-leap ]]'
check 'Leap 15 is refused' '! detect "ID=opensuse-leap
VERSION_ID=15.6" >/dev/null'
check 'Tumbleweed is refused' '! detect "ID=opensuse-tumbleweed" >/dev/null'
check 'Debian is refused' '! detect "ID=debian" >/dev/null'
check 'an unknown --distro is refused' '! "$script" --distro debian >/dev/null 2>&1'

# Captured, not read back from $?: under set -e a failing --help would end
# the script before the check, so the check could only ever pass.
help_status=0; "$script" --help >/dev/null 2>&1 || help_status=$?
check '--help exits 0' '[[ $help_status -eq 0 ]]'

set +e
"$script" --nonsense >/dev/null 2>&1
unknown=$?
set -e
check 'an unknown option exits 2' '[[ $unknown -eq 2 ]]'

# ---- the default applications --------------------------------------------
# Every category the installer sets has to be one default-apps.py knows, and
# every desktop id has to look like one.
known=$(grep -oP '^\s*\("\K[a-z]+' "$project_dir/scripts/default-apps.py")
while IFS=: read -r category desktop_id; do
  [[ -z $category ]] && continue
  check "default-apps.py knows the category '$category'" \
    'grep -qx -- "$category" <<<"$known"'
  check "'$category' is set to a desktop id" '[[ $desktop_id == *.desktop ]]'
done < <(sed -n '/^app_defaults=(/,/^)/p' "$script" | grep -oP '"\K[^"]+(?=")')

if (( failures )); then
  printf 'TESTS FAILED bootstrap (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED bootstrap\n'
