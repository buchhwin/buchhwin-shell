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

# ---- the dry run ---------------------------------------------------------
out=$("$script") || { printf 'FAIL bootstrap: the dry run exited non-zero\n'; exit 1; }

for step in \
  '1. The dnf plugins' '2. Repositories' '3. Packages' \
  '4. The icon font' '5. The shell itself' '6. The session entry' \
  '7. Default applications'; do
  check "the dry run names step '$step'" '[[ $out == *"$step"* ]]'
done

check 'the dry run says it changed nothing' '[[ $out == *"Nothing was changed"* ]]'
check 'the dry run runs nothing (no "+ " command lines)' '[[ $out != *$'"'"'\n  + '"'"'* ]]'

# ---- the options ---------------------------------------------------------
minimal=$("$script" --minimal)
check '--minimal leaves the extras out' '[[ $minimal != *wf-recorder* ]]'
check 'the default run has the extras' '[[ $out == *wf-recorder* ]]'
check '--minimal leaves the applications out' '[[ $minimal != *brave-browser* ]]'
check 'the default run has the applications' '[[ $out == *brave-browser* ]]'
check '--minimal says what it left out' '[[ $minimal == *"--minimal:"* ]]'

skipped=$("$script" --skip-apps)
check '--skip-apps leaves the applications out' '[[ $skipped != *brave-browser* ]]'
check '--skip-apps keeps the extras' '[[ $skipped == *wf-recorder* ]]'

"$script" --help >/dev/null 2>&1
check '--help exits 0' '[[ $? -eq 0 ]]'

set +e
"$script" --nonsense >/dev/null 2>&1
unknown=$?
set -e
check 'an unknown option exits 2' '[[ $unknown -eq 2 ]]'

# ---- the lists -----------------------------------------------------------
# Through --list-packages rather than by parsing the script: the list has one
# owner, and the flag is what docs/testing.md tells people to check against the
# repositories, so it is worth holding to account here.
all_packages=$("$script" --list-packages)
count=$(printf '%s\n' "$all_packages" | wc -l)
unique=$(printf '%s\n' "$all_packages" | sort -u | wc -l)
check "--list-packages lists something" '[[ $count -gt 20 ]]'
check "no package is listed twice ($count listed, $unique distinct)" '[[ $count -eq $unique ]]'
check 'no package name has a stray character' \
  '! printf "%s\n" "$all_packages" | grep -qvE "^[A-Za-z0-9][A-Za-z0-9._+-]*$"'
# The flag has to ignore the filters, or the check it exists for would silently
# skip whatever the current options leave out.
check '--list-packages ignores --minimal' \
  '[[ $("$script" --list-packages --minimal) == "$all_packages" ]]'

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
