#!/usr/bin/env bash
set -euo pipefail

# The shell's own update, for Settings > Updates: the checkout the session
# runs from - what ~/.local/share/buchhwin-shell points at - against the git
# remote it follows.
#
#   shell-update.sh check [--offline]   what the remote has that this has not
#   shell-update.sh apply               fast-forward, re-run install.sh, reload
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
    reload_for_changes "$dir" "$from" "$to"
    if command -v notify-send >/dev/null 2>&1; then
      notify-send --app-name=Updates --icon=system-software-update -- \
        "buchhwin-shell updated" "$(g log -1 --format=%s)" 2>/dev/null || true
    fi
    ;;
  *)
    printf 'Usage: %s check [--offline] | apply\n' "$0" >&2; exit 2 ;;
esac
