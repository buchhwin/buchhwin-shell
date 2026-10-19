#!/usr/bin/env bash
# install/bluetooth-autoenable.sh below a scratch root: it sets AutoEnable in
# the file bluetoothd reads, says what is there, and takes it back exactly.
#
# Reported as "Bluetooth was on again after the restart although I turned it
# off before". Nothing in the shell powers an adapter on; BlueZ's own
# [Policy] AutoEnable defaults to true, commented out in the shipped
# main.conf. bluetoothd reads main.conf and nothing else - an earlier version
# wrote a main.conf.d/ drop-in it never looked at, and this test only checked
# that the drop-in was written.
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 1
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-bttest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
installer="./install/bluetooth-autoenable.sh"
conf="$sandbox/etc/bluetooth/main.conf"
drop="$sandbox/etc/bluetooth/main.conf.d/50-buchhwin-autoenable.conf"
failures=0
check() { if eval "$1"; then :; else printf 'FAIL bluetooth-autoenable: %s\n' "$2"; failures=$((failures + 1)); fi; }

# The value AutoEnable has in [Policy] as BlueZ's GKeyFile reads it: the last
# active line of the key in that section, or "unset" (BlueZ's default, true).
policy_value() {
  awk '/^[[:space:]]*\[/ { policy = ($0 ~ /^[[:space:]]*\[Policy\][[:space:]]*$/); next }
       policy && /^[[:space:]]*AutoEnable[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); value = $0 }
       END { print (value == "" ? "unset" : value) }' "$conf"
}

mkdir -p "$(dirname -- "$conf")"
# Shaped like the shipped file: [Policy] between other sections, the key
# commented out, a value of the same name in another section.
cat > "$conf" <<'CONF'
[General]
#Name = BlueZ
AutoEnable=true

[Policy]
#ReconnectAttempts=7
# AutoEnable defines option to enable all controllers when they are found.
#AutoEnable=true

[AdvMon]
#RSSISamplingPeriod=0xFF
CONF
cp -p "$conf" "$sandbox/main.conf.orig"

check '[[ $("$installer" status --root "$sandbox") == absent:* ]]' 'nothing of ours is reported absent'
check '[[ $(policy_value) == unset ]]' 'the shipped file leaves AutoEnable to BlueZ'
"$installer" off --root "$sandbox" >/dev/null
check '[[ $(policy_value) == false ]]' 'off sets AutoEnable=false in [Policy] of main.conf itself'
check '[[ $(grep -c "^AutoEnable=false$" "$conf") -eq 1 ]]' 'once'
check 'grep -qx "AutoEnable=true" "$conf"' 'and leaves a key of the same name in another section alone'
check '[[ $("$installer" status --root "$sandbox") == installed:* ]]' 'status says installed'
check 'cmp -s "$sandbox/main.conf.orig" "$conf.before-buchhwin"' 'the file as it was is kept beside it'
check '[[ ! -e $sandbox/etc/bluetooth/main.conf.d ]]' 'no drop-in directory BlueZ would not read'
"$installer" off --root "$sandbox" >/dev/null
check '[[ $(grep -c "^AutoEnable=false$" "$conf") -eq 1 && $(policy_value) == false ]]' 'a second off adds nothing'
"$installer" on --root "$sandbox" >/dev/null
check 'cmp -s "$sandbox/main.conf.orig" "$conf"' 'on gives the file back exactly as it was'
check '[[ ! -e $conf.before-buchhwin ]]' 'and drops the copy that is no longer needed'

# An AutoEnable of the user's own in [Policy] is commented out while ours
# holds, and comes back with on.
printf '[Policy]\nAutoEnable = true\nReconnectAttempts=3\n' > "$conf"
cp -p "$conf" "$sandbox/own.orig"
"$installer" off --root "$sandbox" >/dev/null
check '[[ $(policy_value) == false ]]' 'an active AutoEnable of its own gives way'
check 'grep -qx "ReconnectAttempts=3" "$conf"' 'and the rest of [Policy] stays'
"$installer" on --root "$sandbox" >/dev/null
check 'cmp -s "$sandbox/own.orig" "$conf"' 'on brings the user'"'"'s own line back'

# A file without [Policy] gets one; a missing file is BlueZ not installed.
printf '[General]\n#Name = BlueZ\n' > "$conf"
"$installer" off --root "$sandbox" >/dev/null
check '[[ $(policy_value) == false ]]' 'a file without [Policy] gets the section'
rm -f -- "$conf" "$conf.before-buchhwin"
status=0; "$installer" off --root "$sandbox" >/dev/null 2>&1 || status=$?
check '[[ $status -ne 0 && ! -e $conf ]]' 'without main.conf nothing is written (BlueZ is not installed)'

# The earlier version's drop-in goes; one that is not ours stays.
printf '[Policy]\n#AutoEnable=true\n' > "$conf"
mkdir -p "$(dirname -- "$drop")"
printf '# Managed by buchhwin-shell (install/bluetooth-autoenable.sh)\n[Policy]\nAutoEnable=false\n' > "$drop"
check '[[ $("$installer" status --root "$sandbox") == *"stale: "* ]]' 'status names the old drop-in'
"$installer" on --root "$sandbox" >/dev/null
check '[[ ! -e $drop && ! -e $(dirname -- "$drop") ]]' 'on removes the old drop-in and its empty directory'
mkdir -p "$(dirname -- "$drop")"
printf '[Policy]\nAutoEnable=true\n' > "$drop"
"$installer" off --root "$sandbox" >/dev/null
check 'grep -q "^AutoEnable=true$" "$drop"' 'a drop-in that is not ours is left where it is'

if (( failures )); then
  printf 'TESTS FAILED bluetooth-autoenable (%d)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED bluetooth-autoenable\n'
