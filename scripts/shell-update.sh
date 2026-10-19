#!/usr/bin/env bash
set -euo pipefail

# The shell's own update, for Settings > Updates: the checkout the session
# runs from - what ~/.local/share/buchhwin-shell points at - against the git
# remote it follows.
#
#   shell-update.sh check [--offline]   what the remote has that this has not
#   shell-update.sh apply               fast-forward, re-run install.sh, reload,
#                                       and say what else the new version needs
#
# `check` prints "@NAME EXIT" sections the way updates-check.sh does, parsed by
# services/updates/UpdatesLogic.js:
#   @repo     ok | none (not a git checkout) | local (follows no remote), then
#             one line each: directory, branch, upstream, short head
#   @fetch    git fetch; "skipped" with --offline, which nested sessions and
#             the look at start pass - local git only, no network
#   @behind   commits the upstream has that HEAD has not
#   @ahead    commits HEAD has that the upstream has not
#   @dirty    git status --porcelain
#   @log      hash<TAB>subject of the commits behind, newest first, at most 50
#   @end
#
# `apply` does for a clone that follows a remote what scripts/deploy.sh does
# for the stable worktree on the development machine: ff-only, so nothing of
# the user's is ever merged over - a checkout with local changes or local
# commits is refused, and says so; install/install.sh --apply, which is
# idempotent and backs up what it moves; then Hyprland is reloaded when hypr/
# changed and the shell when anything it loads changed (scripts/lib/reload.sh).
# The shell starts this through systemd-run, because the restart it ends in
# would otherwise kill it halfway. A nested test session never gets here.
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/nested-guard.sh
source "$here/lib/nested-guard.sh"
# shellcheck source=lib/reload.sh
source "$here/lib/reload.sh"

installed=${BUCHHWIN_SHELL_PATH:-$HOME/.local/share/buchhwin-shell}
dir=$(readlink -f -- "$installed" 2>/dev/null || true)
action=${1:-check}
offline=0
[[ ${2:-} == --offline ]] && offline=1
section() { printf '@%s %s\n' "$1" "$2"; }
g() { git -C "$dir" "$@"; }
# The shell runs `check` on a timer, with no terminal and nobody at a prompt.
# A remote that wants a password (an HTTPS remote without a stored credential,
# an SSH key with a passphrase and no agent) must fail at once, not sit in a
# prompt until the 60 s timeout - or for ever, with GIT_ASKPASS pointing at a
# graphical helper. The user's own ssh command is kept and only made
# non-interactive.
fetch() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -oBatchMode=yes" \
    timeout 60 git -C "$dir" fetch --quiet "$@"
}

is_checkout() {
  [[ -n $dir && -d $dir ]] || return 1
  local top
  top=$(g rev-parse --show-toplevel 2>/dev/null) || return 1
  [[ $(readlink -f -- "$top") == "$dir" ]]
}
upstream_of() { g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true; }
# `apply` runs inside systemd-run without --wait: nobody reads its status, and
# the Updates page keeps saying "Updating the shell ..." whatever happened. A
# refusal, or a fetch, merge or install that fails under set -e, is told the
# way success is - a notification - with the place the reason went to.
notify_failure() {
  local code=$1
  (( code != 0 )) || return 0
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send --app-name=Updates --icon=dialog-error -- "buchhwin-shell update failed" \
    "It stopped with exit $code; journalctl --user -u buchhwin-shell-update says why." 2>/dev/null || true
}

# What an update cannot do by itself, one line each, for the notification:
# install.sh --apply links the user's side, but the packages a newer version
# lists (install/packages/) need bootstrap.sh, and the system's copies of the
# session entry, the lock screen's PAM files and, on Leap, the Hyprland build
# need their own installers with root rights. An update used to bring none of
# it - the Citrix clipboard bridge arrived without the xclip it reads with,
# a fixed PAM file never reached /etc/pam.d. Only what the update changed is
# named: a package the new version adds and this system does not have yet.
update_notes() {
  local from=$1 to=$2 changed distro name joined count=0
  local -a missing=() names_from=() names_to=()
  changed=$(g diff --name-only "$from" "$to" 2>/dev/null) || return 0
  # shellcheck source=../install/lib/distro.sh
  distro=$(source "$dir/install/lib/distro.sh" && distro_detect 2>/dev/null) || distro=""
  if [[ -n $distro ]] && grep -q "^install/packages/$distro\.sh$" <<<"$changed"; then
    mapfile -t names_from < <(package_names "$from" "$distro")
    mapfile -t names_to < <(package_names "$to" "$distro")
    local -A had=()
    for name in "${names_from[@]}"; do [[ -n $name ]] && had[$name]=1; done
    local -a added=()
    for name in "${names_to[@]}"; do
      [[ -n $name && -z ${had[$name]:-} ]] && added+=("$name")
    done
    if (( ${#added[@]} )); then mapfile -t missing < <(not_installed "$distro" "${added[@]}"); fi
    count=${#missing[@]}
    if (( count )); then
      printf -v joined '%s, ' "${missing[@]}"
      if (( count == 1 )); then
        printf '1 new package (%s): install/bootstrap.sh --apply\n' "${joined%, }"
      else
        printf '%d new packages (%s): install/bootstrap.sh --apply\n' "$count" "${joined%, }"
      fi
    fi
  fi
  if grep -qE '^session/(buchhwin-shell-session-wrapper|buchhwin-shell\.desktop\.in)$' <<<"$changed"; then
    printf 'The session entry changed: sudo install/system-install.sh\n'
  fi
  if pam_changed "$changed" "$distro"; then
    printf "The lock screen's PAM files changed: compare /etc/pam.d/buchhwin-lock* with session/pam/\n"
  fi
  if [[ $distro == opensuse-leap ]] && grep -q '^install/build-hyprland-leap\.sh$' <<<"$changed"; then
    printf "Hyprland's build changed: install/build-hyprland-leap.sh --apply\n"
  fi
}
# Whether the update changed a PAM file this system has. system-install.sh
# installs session/pam/<name> with the suffix of the PAM stack it finds -
# by the distribution's name first, then by the files the stack has - and
# the same rule picks it here: the note came for a .suse file on Arch too.
# The fingerprint lid helper counts wherever it is, and with no known
# distribution every file does, as before.
pam_present() { [[ -e /etc/pam.d/$1 || -e /usr/lib/pam.d/$1 ]]; }
pam_changed() {
  local changed=$1 distro=$2 suffix="" name
  grep -q '^session/pam/' <<<"$changed" || return 1
  [[ -n $distro ]] || return 0
  grep -qx 'session/pam/buchhwin-lid-closed' <<<"$changed" && return 0
  if [[ $distro == arch ]]; then
    suffix=.arch
  elif pam_present common-auth; then
    suffix=.suse
  elif pam_present system-auth && ! pam_present password-auth; then
    suffix=.arch
  elif [[ ! -e /etc/pam.d/system-auth && $distro == opensuse-leap ]]; then
    suffix=.suse
  fi
  for name in buchhwin-lock buchhwin-lock-password; do
    grep -qx "session/pam/$name$suffix" <<<"$changed" && return 0
  done
  return 1
}
# The names a version of the distribution's list installs with every run of
# bootstrap.sh (--minimal too): its bootstrap, core, package and font lists
# (the fonts unless --skip-fonts). The
# list is shell code of the repository's own; read in a subshell.
package_names() {
  (
    bootstrap_packages=() core=() packages=() font_packages=()
    # shellcheck disable=SC1090
    source <(g show "$1:install/packages/$2.sh" 2>/dev/null) >/dev/null 2>&1 || exit 0
    printf '%s\n' "${bootstrap_packages[@]}" "${core[@]}" "${packages[@]}" "${font_packages[@]}"
  )
}
# Of the names given, those this system has nothing installed for.
not_installed() {
  local distro=$1
  shift
  case $distro in
    arch)
      # `pacman -T` prints every dependency nothing installed satisfies.
      command -v pacman >/dev/null 2>&1 || return 0
      pacman -T "$@" 2>/dev/null || true ;;
    *)
      command -v rpm >/dev/null 2>&1 || return 0
      rpm -q --whatprovides "$@" 2>/dev/null | sed -n 's/^no package provides //p' || true ;;
  esac
}

case "$action" in
  check)
    if ! is_checkout; then
      section repo 0; printf 'none\n%s\n' "$dir"; section end 0; exit 0
    fi
    branch=$(g rev-parse --abbrev-ref HEAD)
    upstream=$(upstream_of)
    head=$(g rev-parse --short HEAD)
    if [[ -z $upstream ]]; then
      section repo 0; printf 'local\n%s\n%s\n\n%s\n' "$dir" "$branch" "$head"; section end 0; exit 0
    fi
    section repo 0; printf 'ok\n%s\n%s\n%s\n%s\n' "$dir" "$branch" "$upstream" "$head"
    if (( offline )); then
      section fetch 0; printf 'skipped\n'
    else
      code=0
      out=$(fetch 2>&1) || code=$?
      section fetch "$code"; printf '%s\n' "$out"
    fi
    section behind 0; g rev-list --count 'HEAD..@{u}'
    section ahead 0; g rev-list --count '@{u}..HEAD'
    section dirty 0; g status --porcelain
    section log 0; g log --format='%h%x09%s' -n 50 'HEAD..@{u}'
    section end 0
    ;;
  apply)
    if nested_environment; then
      printf 'shell-update: refusing to update the host from a nested test session\n' >&2; exit 1
    fi
    trap 'notify_failure $?' EXIT
    is_checkout || { printf 'shell-update: %s is not a git checkout\n' "$installed" >&2; exit 1; }
    upstream=$(upstream_of)
    [[ -n $upstream ]] || { printf 'shell-update: %s follows no remote\n' "$dir" >&2; exit 1; }
    [[ -z $(g status --porcelain) ]] || { printf 'shell-update: refusing, %s has local changes\n' "$dir" >&2; exit 1; }
    fetch
    ahead=$(g rev-list --count '@{u}..HEAD')
    (( ahead == 0 )) || { printf 'shell-update: refusing, %s has %s commit(s) the remote does not\n' "$dir" "$ahead" >&2; exit 1; }
    from=$(g rev-parse HEAD)
    to=$(g rev-parse '@{u}')
    if [[ $from == "$to" ]]; then printf 'Already up to date.\n'; exit 0; fi
    g merge --ff-only --quiet '@{u}'
    "$dir/install/install.sh" --apply >/dev/null
    printf 'Updated %s: %s -> %s\n' "$dir" "$(g rev-parse --short "$from")" "$(g rev-parse --short "$to")"
    # A question that fails costs the notes, never the update.
    notes=$(update_notes "$from" "$to" 2>/dev/null) || notes=""
    if [[ -n $notes ]]; then printf '%s\n' "$notes"; fi
    reload_for_changes "$dir" "$from" "$to"
    if command -v notify-send >/dev/null 2>&1; then
      body=$(g log -1 --format=%s)
      if [[ -n $notes ]]; then body+=$'\n'$notes; fi
      notify-send --app-name=Updates --icon=system-software-update -- \
        "buchhwin-shell updated" "$body" 2>/dev/null || true
    fi
    ;;
  *)
    printf 'Usage: %s check [--offline] | apply\n' "$0" >&2; exit 2 ;;
esac
