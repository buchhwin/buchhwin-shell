#!/usr/bin/env bash
# install/bluetooth-autoenable.sh below a scratch root: it writes the drop-in,
# says what is there, and takes it away again.
#
# Reported as "Bluetooth was on again after the restart although I turned it
# off before". Nothing in the shell powers an adapter on; BlueZ's own
# [Policy] AutoEnable defaults to true and Fedora ships it commented out.
set -uo pipefail
cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." || exit 1
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-bttest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
installer="./install/bluetooth-autoenable.sh"
drop="$sandbox/etc/bluetooth/main.conf.d/50-buchhwin-autoenable.conf"
failures=0
check() { if eval "$1"; then :; else printf 'FAIL bluetooth-autoenable: %s\n' "$2"; failures=$((failures + 1)); fi; }

check '[[ $("$installer" status --root "$sandbox") == absent:* ]]' 'nothing there is reported absent'
"$installer" off --root "$sandbox" >/dev/null
check '[[ -f $drop ]]' 'off writes the drop-in'
check 'grep -q "^AutoEnable=false$" "$drop"' 'and says AutoEnable=false'
check 'grep -q "^\[Policy\]$" "$drop"' 'under the section BlueZ reads it in'
check '[[ $("$installer" status --root "$sandbox") == installed:* ]]' 'status says installed'

# A drop-in of the same name that is not ours is left where it is.
printf '[Policy]\nAutoEnable=true\n' > "$drop"
check '[[ $("$installer" status --root "$sandbox") == absent:* ]]' 'a drop-in that is not ours is not claimed'
"$installer" on --root "$sandbox" >/dev/null
check 'grep -q "^AutoEnable=true$" "$drop"' 'and on does not delete it'

rm -f -- "$drop"
"$installer" off --root "$sandbox" >/dev/null
"$installer" on --root "$sandbox" >/dev/null
check '[[ ! -e $drop ]]' 'on removes our own file'

if (( failures )); then
  printf 'TESTS FAILED bluetooth-autoenable (%d)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED bluetooth-autoenable\n'
