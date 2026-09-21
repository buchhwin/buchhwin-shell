#!/usr/bin/env bash
set -euo pipefail

# Optional, system-wide: skip pam_fprintd while the laptop lid is closed, so
# sudo, polkit, TTY logins and the lock screen ask for the password at once on
# a dock. Called by install/system-install.sh --fingerprint-lid /
# --fingerprint-lid-remove.
#
#   fingerprint-lid.sh install|remove|status [--root DIR --authselect CMD]
#   fingerprint-lid.sh line      prints the PAM line (tests)
#
# Fedora generates /etc/pam.d/system-auth with authselect, so a manual edit
# would be overwritten. install creates the custom profile
# custom/buchhwin-lid from the active profile (e.g. "local") and adds one line
# directly before pam_fprintd, under the same with-fingerprint condition:
#
#   auth [success=1 default=ignore] pam_exec.so quiet quiet_log /usr/local/bin/buchhwin-lid-closed
#
# pam.conf(5): success=1 jumps over the next module (pam_fprintd) and, for
# pam_authenticate, has the effect of "ignore" (the line never grants access);
# every other result (lid open, missing or blocked helper, errors) is ignored
# and the normal stack runs. Before selecting the profile, `authselect test`
# must show exactly that one added line compared with the active profile;
# otherwise nothing is selected. After selecting, the live file is checked and
# the previous profile is restored on any mismatch. authselect keeps a backup
# (authselect backup-list). remove selects the previous profile with the
# features enabled at that time and deletes the helper and the custom profile.
#
# --root DIR with --authselect CMD works below DIR with a stand-in authselect
# (tests/fingerprint-lid-install-test.sh); otherwise root is needed.

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile_name=buchhwin-lid
helper_source="$project_dir/session/pam/buchhwin-lid-closed"
helper_path=/usr/local/bin/buchhwin-lid-closed
pam_line="auth        [success=1 default=ignore]                   pam_exec.so quiet quiet_log $helper_path"
condition='{include if "with-fingerprint"}'

action=${1:-}
case "$action" in
  install|remove|status) ;;
  line) printf '%s\n' "$pam_line"; exit 0 ;;
  *) printf 'Usage: %s install|remove|status [--root DIR --authselect CMD]\n' "$0" >&2; exit 2 ;;
esac
shift

root=""
authselect_cmd=""
while (( $# )); do
  case "$1" in
    --root) root=${2:?--root needs a directory}; shift 2 ;;
    --authselect) authselect_cmd=${2:?--authselect needs a command}; shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if [[ -n $authselect_cmd && -z $root ]]; then
  printf '--authselect is only for tests with --root\n' >&2
  exit 2
fi
if [[ -n $root && -z $authselect_cmd ]]; then
  printf '--root needs --authselect (the real authselect has no root option)\n' >&2
  exit 2
fi
[[ -z $authselect_cmd ]] && authselect_cmd=authselect
if [[ -z $root && $action != status ]] && (( EUID != 0 )); then
  printf 'Run this step as root: sudo %s/install/system-install.sh --fingerprint-%s\n' "$project_dir" \
    "$([[ $action == install ]] && printf lid || printf lid-remove)" >&2
  exit 1
fi

custom_dir="$root/etc/authselect/custom/$profile_name"
live_file="$root/etc/authselect/system-auth"
helper_file="$root$helper_path"
state_dir="$root/var/lib/buchhwin-shell/fingerprint-lid"

# Word splitting is intended: tests pass "python3 STUB".
authselect() { command $authselect_cmd "$@"; }

# Runs the installed helper; below --root with test lid files and no UPower.
run_helper() {
  if [[ -n $root ]]; then
    timeout 5 "$helper_file" --lid-dir "$root/proc/acpi/button/lid" --no-upower
  else
    timeout 5 "$helper_file"
  fi
}

# Whitespace-insensitive form of a PAM line.
squeeze() { printf '%s' "$1" | tr -s ' \t' '  ' | sed 's/^ //; s/ $//'; }

# Reads the active profile into $profile and its features into $features.
read_current() {
  local raw
  raw=$(authselect current --raw 2>/dev/null) || return 1
  read -r -a words <<<"$raw"
  (( ${#words[@]} )) || return 1
  profile=${words[0]}
  features=("${words[@]:1}")
}

has_feature() {
  local feature
  for feature in "${features[@]}"; do [[ $feature == "$1" ]] && return 0; done
  return 1
}

# $1: rendered system-auth of the active profile, $2: of the custom profile.
# True when $2 is $1 plus exactly our line directly before pam_fprintd.
rendered_ok() {
  local -a base new rest
  mapfile -t base <<<"$1"
  mapfile -t new <<<"$2"
  local i hits=0 at=-1
  for i in "${!new[@]}"; do
    if [[ ${new[i]} == *"$helper_path"* ]]; then hits=$((hits + 1)); at=$i; fi
  done
  (( hits == 1 )) || return 1
  [[ $(squeeze "${new[at]}") == "$(squeeze "$pam_line")" ]] || return 1
  [[ $(squeeze "${new[at + 1]:-}") =~ ^auth\ sufficient\ pam_fprintd\.so ]] || return 1
  rest=("${new[@]:0:at}" "${new[@]:at + 1}")
  [[ $(printf '%s\n' "${rest[@]}") == "$(printf '%s\n' "${base[@]}")" ]]
}

# The generated file in use: our line exactly once, right before pam_fprintd.
live_ok() {
  [[ -r $live_file ]] || return 1
  local -a lines
  mapfile -t lines < "$live_file"
  local i hits=0 at=-1
  for i in "${!lines[@]}"; do
    if [[ ${lines[i]} == *"$helper_path"* ]]; then hits=$((hits + 1)); at=$i; fi
  done
  (( hits == 1 )) || return 1
  [[ $(squeeze "${lines[at]}") == "$(squeeze "$pam_line")" ]] || return 1
  [[ $(squeeze "${lines[at + 1]:-}") =~ ^auth\ sufficient\ pam_fprintd\.so ]]
}

live_has_helper() { [[ -r $live_file ]] && grep -qF -- "$helper_path" "$live_file"; }

rescue_hint() {
  printf 'If sudo stops working, run from a root shell (or a TTY login as root):\n' >&2
  printf '  authselect select %s %s\n' "$1" "${features[*]}" >&2
  printf '  authselect backup-list; authselect backup-restore NAME\n' >&2
}

# Undo a partial install (the active profile was not changed) and exit.
abort_install() {
  rm -rf -- "$custom_dir" "$state_dir"
  rm -f -- "$helper_file"
  printf '%s\n' "$1" >&2
  exit 1
}

install_lid() {
  if ! read_current; then
    printf 'authselect does not manage the PAM configuration here (authselect current failed).\n' >&2
    printf 'Nothing changed. Add this line by hand directly before pam_fprintd in the auth section, keeping a root shell open:\n  %s\n' "$pam_line" >&2
    exit 1
  fi
  if [[ $profile == "custom/$profile_name" ]]; then
    if live_ok; then
      printf 'Already installed (profile custom/%s is active).\n' "$profile_name"
      install -Dm0755 -- "$helper_source" "$helper_file"
      printf 'Helper updated: %s\n' "$helper_path"
      printf 'To rebuild after a Fedora upgrade: --fingerprint-lid-remove, then --fingerprint-lid.\n'
      exit 0
    fi
    printf 'custom/%s is active but the generated system-auth does not match; run --fingerprint-lid-remove first.\n' "$profile_name" >&2
    exit 1
  fi
  if [[ $profile == custom/* ]]; then
    printf 'The active authselect profile is %s (a custom profile). Nothing changed.\n' "$profile" >&2
    printf 'Add this line to its system-auth directly before pam_fprintd, with the same condition:\n  %s %s\n' "$pam_line" "$condition" >&2
    exit 1
  fi
  if ! has_feature with-fingerprint; then
    printf 'Fingerprint login is not enabled in authselect (feature with-fingerprint). Nothing changed.\n' >&2
    exit 1
  fi
  if ! authselect check >/dev/null 2>&1; then
    printf 'authselect check reports manual changes to the PAM files. Nothing changed.\n' >&2
    exit 1
  fi

  # The helper must answer quickly with 0 or 1 before PAM depends on it.
  install -Dm0755 -- "$helper_source" "$helper_file"
  command -v restorecon >/dev/null 2>&1 && [[ -z $root ]] && restorecon -F "$helper_file" 2>/dev/null || true
  local code=0
  run_helper || code=$?
  if (( code != 0 && code != 1 )); then
    abort_install "The lid helper did not work (exit $code). Nothing changed."
  fi
  printf 'Installed %s (lid is %s now).\n' "$helper_path" "$([[ $code == 0 ]] && printf closed || printf 'open or unknown')"

  # A leftover, inactive custom profile is rebuilt from the active one.
  rm -rf -- "$custom_dir"
  if ! authselect create-profile "$profile_name" -b "$profile" --symlink-meta --symlink-nsswitch --symlink-dconf >/dev/null; then
    abort_install "authselect create-profile failed. Nothing changed."
  fi
  local template="$custom_dir/system-auth"
  local matches
  matches=$(grep -cE '^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so' "$template" || true)
  if [[ $matches != 1 ]] || ! grep -E '^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so' "$template" | grep -qF -- "$condition"; then
    abort_install "Unexpected pam_fprintd line(s) in the $profile profile. Nothing changed."
  fi
  local line_with_condition="$pam_line $condition"
  awk -v add="$line_with_condition" '
    /^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so/ { print add }
    { print }' "$template" > "$template.new"
  chmod 0644 -- "$template.new"
  mv -f -- "$template.new" "$template"

  local base_render new_render
  base_render=$(authselect test "$profile" "${features[@]}" --system-auth) || base_render=""
  new_render=$(authselect test "custom/$profile_name" "${features[@]}" --system-auth) || new_render=""
  if [[ -z $base_render ]] || ! rendered_ok "$base_render" "$new_render"; then
    abort_install "The new profile would change more than the one line. Nothing changed."
  fi

  mkdir -p -- "$state_dir"
  printf '%s\n' "$profile" > "$state_dir/base-profile"
  local backup
  backup="buchhwin-before-lid-$(date +%Y%m%d-%H%M%S)"
  if ! authselect select "custom/$profile_name" "${features[@]}" -q --backup="$backup" >/dev/null; then
    local wanted=$profile
    if read_current && [[ $profile == "$wanted" ]] && ! live_has_helper; then
      abort_install "authselect select failed. Nothing changed."
    fi
    profile=$wanted
    printf 'authselect select failed; selecting %s again.\n' "$profile" >&2
    if ! authselect select "$profile" "${features[@]}" -q >/dev/null; then
      rescue_hint "$profile"
      exit 1
    fi
    abort_install "Restored $profile."
  fi
  if ! live_ok || ! authselect check >/dev/null 2>&1; then
    printf 'The generated system-auth is not as expected; selecting %s again.\n' "$profile" >&2
    if ! authselect select "$profile" "${features[@]}" -q >/dev/null; then
      rescue_hint "$profile"
      exit 1
    fi
    abort_install "Restored $profile."
  fi
  printf 'Selected authselect profile custom/%s (features: %s; backup %s).\n' "$profile_name" "${features[*]}" "$backup"
  printf 'sudo, polkit, logins and the lock screen skip the fingerprint while the lid is closed.\n'
  printf 'Test in a NEW terminal while this one stays open: sudo -k; sudo true\n'
  printf 'Undo: sudo %s/install/system-install.sh --fingerprint-lid-remove\n' "$project_dir"
}

remove_lid() {
  local base=local
  [[ -r $state_dir/base-profile ]] && base=$(<"$state_dir/base-profile")
  if read_current && [[ $profile == "custom/$profile_name" ]]; then
    local backup
    backup="buchhwin-before-lid-remove-$(date +%Y%m%d-%H%M%S)"
    if ! authselect select "$base" "${features[@]}" -q --backup="$backup" >/dev/null; then
      printf 'authselect select %s failed; custom/%s stays active.\n' "$base" "$profile_name" >&2
      exit 1
    fi
    if ! read_current || [[ $profile != "$base" ]] || live_has_helper; then
      printf 'The profile switch did not apply as expected; the helper and profile are kept.\n' >&2
      rescue_hint "$base"
      exit 1
    fi
    printf 'Selected authselect profile %s again (features: %s; backup %s).\n' "$base" "${features[*]}" "$backup"
  elif live_has_helper; then
    printf 'system-auth still calls %s but custom/%s is not active; nothing removed.\n' "$helper_path" "$profile_name" >&2
    exit 1
  fi
  rm -rf -- "$custom_dir" "$state_dir"
  rm -f -- "$helper_file"
  printf 'Removed the lid check; the fingerprint is offered as before.\n'
}

status_lid() {
  if read_current; then
    printf 'authselect profile: %s %s\n' "$profile" "${features[*]}"
  else
    printf 'authselect profile: unknown\n'
  fi
  if live_ok; then printf 'system-auth: skips pam_fprintd while the lid is closed\n'
  elif live_has_helper; then printf 'system-auth: calls the helper in an unexpected way\n'
  else printf 'system-auth: not installed\n'; fi
  if [[ -x $helper_file ]]; then
    local code=0
    run_helper || code=$?
    printf 'helper: %s (lid %s)\n' "$helper_path" "$([[ $code == 0 ]] && printf closed || printf 'open or unknown')"
  else
    printf 'helper: not installed\n'
  fi
}

case "$action" in
  install) install_lid ;;
  remove) remove_lid ;;
  status) status_lid ;;
esac
