#!/usr/bin/env bash
set -euo pipefail

# install/logind-lid.sh below a scratch root: it writes the drop-in, says what
# is there, keeps a drop-in of the same name that is not this project's, and
# puts it back on remove. The reason the script exists at all is in its own
# header - a login with the lid shut suspended the session one second after it
# started, because logind re-reads the lid when a session appears.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-logindtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
installer="$project_dir/install/logind-lid.sh"
drop="$sandbox/etc/systemd/logind.conf.d/50-buchhwin.conf"
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL logind-lid: %s\n' "$2"; failures=$((failures + 1)); fi
}

check '[[ $("$installer" status --root "$sandbox") == absent:* ]]' 'nothing there is reported absent'

"$installer" install --root "$sandbox" >/dev/null
check '[[ -f $drop ]]' 'install writes the drop-in'
check 'grep -q "^HandleLidSwitch=ignore$" "$drop"' 'logind is told to ignore the lid'
check 'grep -q "^HandleLidSwitchExternalPower=ignore$" "$drop"' 'on external power too'
check 'grep -q "^HandleLidSwitchDocked=ignore$" "$drop"' 'and docked'
check '[[ $("$installer" status --root "$sandbox") == installed:* ]]' 'status says installed'

# Running it twice must not stack backups of its own file.
"$installer" install --root "$sandbox" >/dev/null
check '[[ ! -e $drop.before-buchhwin ]]' 'installing over its own file keeps no backup'

# A drop-in of the same name that somebody else wrote is kept, not lost. This
# is the case that mattered here: the machine already had one, saying
# HandleLidSwitch=suspend, and that is what suspended the session at login.
printf '[Login]\nHandleLidSwitch=suspend\n' > "$drop"
check '[[ $("$installer" status --root "$sandbox") == foreign:* ]]' 'a foreign drop-in is named as one'
"$installer" install --root "$sandbox" >/dev/null
check 'grep -q "^HandleLidSwitch=suspend$" "$drop.before-buchhwin"' 'the foreign one is kept beside it'
check 'grep -q "^HandleLidSwitch=ignore$" "$drop"' 'and ours is in place'

"$installer" remove --root "$sandbox" >/dev/null
check 'grep -q "^HandleLidSwitch=suspend$" "$drop"' 'remove puts the foreign one back'
check '[[ ! -e $drop.before-buchhwin ]]' 'and takes the backup with it'

# With nothing of ours there, remove leaves the file alone.
"$installer" remove --root "$sandbox" >/dev/null
check 'grep -q "^HandleLidSwitch=suspend$" "$drop"' 'remove leaves a file that is not ours'

# The backup is the original, and it is never overwritten: a foreign file
# found a second time (ours replaced in between) goes beside it.
rm -f -- "$drop" "$drop".before-buchhwin*
printf '[Login]\nHandleLidSwitch=suspend\n' > "$drop"
"$installer" install --root "$sandbox" >/dev/null
printf '[Login]\nHandleLidSwitch=hibernate\n' > "$drop"
"$installer" install --root "$sandbox" >/dev/null
check 'grep -q "^HandleLidSwitch=suspend$" "$drop.before-buchhwin"' 'a second foreign file does not overwrite the original backup'
check 'grep -q "^HandleLidSwitch=hibernate$" "$drop".before-buchhwin-* 2>/dev/null' 'and is kept beside it'
check 'grep -q "^HandleLidSwitch=ignore$" "$drop"' 'with ours in place again'
"$installer" remove --root "$sandbox" >/dev/null
check 'grep -q "^HandleLidSwitch=suspend$" "$drop"' 'remove puts the original back'
rm -f -- "$drop" "$drop".before-buchhwin*

# And with only ours there, remove deletes it.
rm -f -- "$drop"
"$installer" install --root "$sandbox" >/dev/null
"$installer" remove --root "$sandbox" >/dev/null
check '[[ ! -e $drop ]]' 'remove deletes our own file'

if (( failures )); then
  printf 'TESTS FAILED logind-lid (%d)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED logind-lid\n'
