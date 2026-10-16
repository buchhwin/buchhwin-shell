# shellcheck shell=bash
# Reload the running session after the checkout it runs from moved: Hyprland
# only when its configuration changed, the shell when anything it loads
# changed. Shared by scripts/deploy.sh (the stable worktree on the development
# machine) and scripts/shell-update.sh (a clone that follows its remote, on
# any other). Source this file.

# hyprland_session: is there a Hyprland session whose shell a restart would
# replace? (scripts/lib/nested-guard.sh, shared with reload-shell.sh.)
# shellcheck source=nested-guard.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/nested-guard.sh"

# Hyprland watches its configuration and reloads by itself, and a checkout
# replaces a file by removing and writing it - so it can read exactly while the
# file is gone and leave "cannot open hyprland.lua" on screen although the
# configuration is fine. An explicit reload afterwards clears that, which is
# why this also runs when the caller was started from outside the session (no
# HYPRLAND_INSTANCE_SIGNATURE) and why it checks the result.
# Hyprland built into the home directory (openSUSE Leap) on PATH, as in the session.
# shellcheck source=hyprland-prefix.sh
if [[ -r "$(dirname -- "${BASH_SOURCE[0]}")/hyprland-prefix.sh" ]]; then source "$(dirname -- "${BASH_SOURCE[0]}")/hyprland-prefix.sh"; fi
reload_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  local signature
  # The caller's session when its socket is there, else the one instance
  # (hyprland_session): more than one means a nested test session is
  # running, and a signature without its socket is a Hyprland that is gone.
  signature=$(hyprland_session) || { printf 'Hyprland was not reloaded (no session found).\n'; return 0; }
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl reload >/dev/null 2>&1 || return 0
  if [[ -n $(HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl configerrors 2>/dev/null | tr -d '[:space:]') ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl reload >/dev/null 2>&1 || true
  fi
  printf 'Reloaded the Hyprland configuration.\n'
}

# reload_for_changes DIR FROM TO - DIR is the checkout the session runs from,
# FROM and TO the commits it moved between.
reload_for_changes() {
  local dir=$1 from=$2 to=$3 changed
  changed=$(git -C "$dir" diff --name-only "$from" "$to")
  # An empty diff is one empty line to a here-string, and `grep -v` matches it
  # against nothing and succeeds - so a deploy that changed no file at all
  # restarted the shell and said so. The same predicate is what keeps a
  # docs-only deploy from restarting it, so it has to be right about nothing
  # too.
  if [[ -z $changed ]]; then
    printf 'No files changed; the shell keeps running.\n'
    return 0
  fi
  if grep -q '^hypr/' <<<"$changed"; then
    reload_hyprland
  fi
  # The session's units are links into the checkout (install.sh); the user
  # manager reads them again only when told. The shell itself never loads
  # them.
  if grep -q '^systemd/' <<<"$changed"; then
    if systemctl --user daemon-reload >/dev/null 2>&1; then
      printf 'Reloaded the user units.\n'
    fi
  fi
  # What the running shell never reads restarts nothing: the page's own files
  # (.github/, LICENSE, the Markdown), the tests and installers, the zsh files
  # and completion a terminal reads when it starts, and the units above.
  # scripts/ stays: drives.py, the Bluetooth agent, the clipboard bridge and
  # the KDE Connect helper run for as long as the shell does, and only a
  # restart starts them from the new files (round 12, scripts#9).
  if ! grep -qvE '^(hypr/|[^/]+\.md$|docs/|Promt$|tests/|install/|session/sddm/|\.gitignore$|\.github/|LICENSE$|shell-completion/|zsh/|systemd/)' <<<"$changed"; then
    printf 'No shell files changed; the shell keeps running.\n'
  elif ! hyprland_session >/dev/null; then
    # A deploy from Plasma (or from a terminal whose Hyprland has gone): no
    # shell of this session to replace, and start-shell.sh would refuse a new
    # one. The next Hyprland login starts it from the new files.
    printf 'No Hyprland session found; the shell was not restarted and starts from the new files at the next login.\n'
  else
    "$dir/scripts/reload-shell.sh"
    printf 'Restarted the shell.\n'
  fi
}
