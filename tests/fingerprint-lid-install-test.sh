#!/usr/bin/env bash
set -euo pipefail

# install/fingerprint-lid.sh below a scratch root with a stand-in authselect
# (tests/fixtures/authselect): the custom profile adds exactly one line before
# pam_fprintd, features are kept, refusals change nothing, remove restores the
# generated system-auth byte for byte. Also the lid helper with test lid files.
# The PAM control semantics are tested with the real libpam in
# tests/python/pam_lid_test.py.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-lidtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
installer="$project_dir/install/fingerprint-lid.sh"
helper="$project_dir/session/pam/buchhwin-lid-closed"
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL fingerprint-lid: %s\n' "$2"; failures=$((failures + 1)); fi
}

# A fresh root with the Fedora "local" profile selected with fingerprint login.
make_root() {
  local root=$1; shift
  mkdir -p "$root/usr/share/authselect/default" "$root/proc/acpi/button/lid/LID"
  cp -r "$project_dir/tests/fixtures/authselect/local" "$root/usr/share/authselect/default/"
  printf 'state:      open\n' > "$root/proc/acpi/button/lid/LID/state"
  python3 "$project_dir/tests/fixtures/authselect/authselect-stub.py" "$root" select local "$@" >/dev/null
  rm -f "$root/authselect-calls.log"
}
run() {
  local root=$1; shift
  "$installer" "$@" --root "$root" --authselect "python3 $project_dir/tests/fixtures/authselect/authselect-stub.py $root"
}
# Runs an installer action that must succeed; its output lands in $output.
output=""
must() {
  local rc=0
  output=$(run "$@" 2>&1) || rc=$?
  (( rc == 0 )) || { printf 'FAIL fingerprint-lid: %s exited %s: %s\n' "${*:2}" "$rc" "$output"; failures=$((failures + 1)); }
}
line=$("$installer" line)
squeeze() { tr -s ' \t' ' ' <<<"$1" | sed 's/ $//'; }

# Lid helper
lids="$sandbox/lids"
mkdir -p "$lids/open/LID" "$lids/closed/LID" "$lids/two/LID0" "$lids/two/LID1" "$lids/garbage/LID" "$lids/none"
printf 'state:      open\n' > "$lids/open/LID/state"
printf 'state:      closed\n' > "$lids/closed/LID/state"
printf 'state:      open\n' > "$lids/two/LID0/state"
printf 'state:      closed\n' > "$lids/two/LID1/state"
printf '\0\1' > "$lids/garbage/LID/state"
code() { local rc=0; "$@" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }
check '[[ $(code "$helper" --lid-dir "$lids/closed" --no-upower) == 0 ]]' "closed lid exits 0"
check '[[ $(code "$helper" --lid-dir "$lids/open" --no-upower) == 1 ]]' "open lid exits 1"
check '[[ $(code "$helper" --lid-dir "$lids/two" --no-upower) == 0 ]]' "any closed lid counts"
check '[[ $(code "$helper" --lid-dir "$lids/garbage" --no-upower) == 1 ]]' "unreadable state counts as open"
check '[[ $(code "$helper" --lid-dir "$lids/none" --no-upower) == 1 ]]' "no lid counts as open"
check '[[ $(code "$helper" --bogus) == 2 ]]' "unknown option fails (the PAM line then ignores it)"
check '[[ $(code env PATH=/nonexistent "$helper" --lid-dir "$lids/closed" --no-upower) == 0 ]]' "does not depend on the caller PATH"

# Option checks (no root needed for these refusals)
check '! "$installer" install --authselect true >/dev/null 2>&1' "--authselect needs --root"
check '! "$installer" install --root "$sandbox/x" >/dev/null 2>&1' "--root needs --authselect"
if (( EUID != 0 )); then
  check '! "$installer" install >/dev/null 2>&1' "real install needs root"
fi

# Install
root="$sandbox/root"
make_root "$root" with-silent-lastlog with-mdns4 with-fingerprint
cp -p "$root/etc/authselect/system-auth" "$sandbox/system-auth.orig"
cp -p "$root/etc/authselect/authselect.conf" "$sandbox/authselect.conf.orig"
must "$root" install
check '[[ -x $root/usr/local/bin/buchhwin-lid-closed ]] && cmp -s "$helper" "$root/usr/local/bin/buchhwin-lid-closed"' "helper installed"
check '[[ $(stat -c %a "$root/usr/local/bin/buchhwin-lid-closed") == 755 ]]' "helper mode 0755"
check 'grep -qx "custom/buchhwin-lid" <(head -n1 "$root/etc/authselect/authselect.conf")' "custom profile selected"
check '[[ $(tail -n +2 "$root/etc/authselect/authselect.conf") == $(tail -n +2 "$sandbox/authselect.conf.orig") ]]' "features kept"
check 'grep -q -- "--backup=buchhwin-before-lid-" "$root/authselect-calls.log"' "authselect backup requested"
check '[[ $(<"$root/var/lib/buchhwin-shell/fingerprint-lid/base-profile") == local ]]' "base profile recorded"
template="$root/etc/authselect/custom/buchhwin-lid/system-auth"
check '[[ $(grep -c buchhwin-lid-closed "$template") == 1 ]]' "one template line"
check 'grep -B0 -A1 buchhwin-lid-closed "$template" | tail -n1 | grep -q "pam_fprintd.so"' "template line before pam_fprintd"
check 'grep buchhwin-lid-closed "$template" | grep -qF "{include if \"with-fingerprint\"}"' "same condition as pam_fprintd"
check 'cmp -s <(grep -v buchhwin-lid-closed "$template") "$root/usr/share/authselect/default/local/system-auth"' "template otherwise unchanged"
mapfile -t live < "$root/etc/authselect/system-auth"
at=-1
for i in "${!live[@]}"; do [[ ${live[i]} == *buchhwin-lid-closed* ]] && at=$i; done
check '(( at > 0 )) && [[ $(squeeze "${live[at]}") == "$(squeeze "$line")" ]]' "live line is exact"
check '[[ ${live[at + 1]} == *"sufficient"*"pam_fprintd.so"* ]]' "live line directly before pam_fprintd"
check 'cmp -s <(grep -v buchhwin-lid-closed "$root/etc/authselect/system-auth") "$sandbox/system-auth.orig"' "live file otherwise identical"
check 'grep -q "sudo -k; sudo true" <<<"$output"' "install prints the sudo test"
must "$root" status
check 'grep -q "skips pam_fprintd while the lid is closed" <<<"$output" && grep -q "lid open" <<<"$output"' "status reports the stack and the lid"

# Second install keeps everything
cp -p "$root/etc/authselect/system-auth" "$sandbox/system-auth.installed"
must "$root" install
check 'grep -q "Already installed" <<<"$output" && cmp -s "$sandbox/system-auth.installed" "$root/etc/authselect/system-auth"' "second install is a no-op"

# Remove restores the generated file exactly
must "$root" remove
check 'cmp -s "$sandbox/system-auth.orig" "$root/etc/authselect/system-auth"' "system-auth restored byte for byte"
check 'cmp -s "$sandbox/authselect.conf.orig" "$root/etc/authselect/authselect.conf"' "profile and features restored"
check '[[ ! -e $root/usr/local/bin/buchhwin-lid-closed && ! -e $root/etc/authselect/custom/buchhwin-lid && ! -e $root/var/lib/buchhwin-shell/fingerprint-lid ]]' "helper, profile and state removed"
must "$root" remove
check 'cmp -s "$sandbox/system-auth.orig" "$root/etc/authselect/system-auth"' "second remove changes nothing"

# Features changed while installed are kept on remove
must "$root" install
python3 "$project_dir/tests/fixtures/authselect/authselect-stub.py" "$root" select custom/buchhwin-lid with-fingerprint with-faillock >/dev/null
must "$root" remove
check '[[ $(tr "\n" " " < "$root/etc/authselect/authselect.conf") == "local with-fingerprint with-faillock " ]]' "remove keeps later feature changes"
check '! grep -q buchhwin-lid-closed "$root/etc/authselect/system-auth"' "no helper line after remove"

# Refusals change nothing
refused() {
  local name=$1 root=$2
  local before="$sandbox/$name.before"
  cp -p "$root/etc/authselect/system-auth" "$before"
  if run "$root" install >/dev/null 2>&1; then
    printf 'FAIL fingerprint-lid: %s: install should refuse\n' "$name"; failures=$((failures + 1))
  fi
  check 'cmp -s "$before" "$root/etc/authselect/system-auth"' "$name: system-auth unchanged"
  check '[[ ! -e $root/etc/authselect/custom/buchhwin-lid && ! -e $root/usr/local/bin/buchhwin-lid-closed ]]' "$name: no custom profile or helper left"
  check '! grep -q "^select" "$root/authselect-calls.log" 2>/dev/null' "$name: nothing selected"
}
make_root "$sandbox/nofp" with-silent-lastlog
refused "without with-fingerprint" "$sandbox/nofp"
make_root "$sandbox/check" with-fingerprint
touch "$sandbox/check/authselect-fail-check"
refused "authselect check fails" "$sandbox/check"
make_root "$sandbox/double" with-fingerprint
printf 'auth        sufficient                                   pam_fprintd.so  {include if "with-fingerprint"}\n' \
  >> "$sandbox/double/usr/share/authselect/default/local/system-auth"
refused "two pam_fprintd lines" "$sandbox/double"
make_root "$sandbox/uncond" with-fingerprint
sed -i 's|^\(auth *sufficient *pam_fprintd.so\).*|\1|' "$sandbox/uncond/usr/share/authselect/default/local/system-auth"
refused "pam_fprintd without the feature condition" "$sandbox/uncond"
make_root "$sandbox/other" with-fingerprint
mkdir -p "$sandbox/other/etc/authselect/custom/mine"
cp "$sandbox/other/usr/share/authselect/default/local/system-auth" "$sandbox/other/etc/authselect/custom/mine/"
python3 "$project_dir/tests/fixtures/authselect/authselect-stub.py" "$sandbox/other" select custom/mine with-fingerprint >/dev/null
rm -f "$sandbox/other/authselect-calls.log"
cp -p "$sandbox/other/etc/authselect/system-auth" "$sandbox/other.before"
check '! run "$sandbox/other" install >/dev/null 2>&1 && cmp -s "$sandbox/other.before" "$sandbox/other/etc/authselect/system-auth"' "another custom profile is left alone"

# select failure: the previous profile stays and nothing is left behind
make_root "$sandbox/selfail" with-fingerprint
cp -p "$sandbox/selfail/etc/authselect/system-auth" "$sandbox/selfail.before"
touch "$sandbox/selfail/authselect-fail-select"
check '! run "$sandbox/selfail" install >/dev/null 2>&1' "failing select is reported"
check 'cmp -s "$sandbox/selfail.before" "$sandbox/selfail/etc/authselect/system-auth" && [[ $(head -n1 "$sandbox/selfail/etc/authselect/authselect.conf") == local ]]' "failing select keeps the profile"
check '[[ ! -e $sandbox/selfail/etc/authselect/custom/buchhwin-lid && ! -e $sandbox/selfail/var/lib/buchhwin-shell/fingerprint-lid && ! -e $sandbox/selfail/usr/local/bin/buchhwin-lid-closed ]]' "failing select cleans up"

if (( failures )); then
  printf 'TESTS FAILED fingerprint-lid (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED fingerprint-lid\n'
