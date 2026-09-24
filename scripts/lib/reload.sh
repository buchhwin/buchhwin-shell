# shellcheck shell=bash
# Reload the running session after the checkout it runs from moved: Hyprland
# only when its configuration changed, the shell when anything it loads
# changed. Shared by scripts/deploy.sh (the stable worktree on the development
# machine) and scripts/shell-update.sh (a clone that follows its remote, on
# any other). Source this file.

# Hyprland watches its configuration and reloads by itself, and a checkout
# replaces a file by removing and writing it - so it can read exactly while the
# file is gone and leave "cannot open hyprland.lua" on screen although the
# configuration is fine. An explicit reload afterwards clears that, which is
# why this also runs when the caller was started from outside the session (no
# HYPRLAND_INSTANCE_SIGNATURE) and why it checks the result.
reload_hyprland() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  local signature=${HYPRLAND_INSTANCE_SIGNATURE:-} instances
  if [[ -z $signature ]]; then
    instances=$(hyprctl instances 2>/dev/null | grep -c '^instance ' || true)
    # More than one means a nested test session is running: never guess which.
    [[ $instances == 1 ]] || { printf 'Hyprland was not reloaded (no session found).\n'; return 0; }
    signature=$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)
    [[ -n $signature ]] || return 0
  fi
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
  if grep -qvE '^(hypr/|[^/]+\.md$|docs/|Promt$|tests/|install/|session/sddm/|\.gitignore$)' <<<"$changed"; then
    "$dir/scripts/reload-shell.sh"
    printf 'Restarted the shell.\n'
  else
    printf 'No shell files changed; the shell keeps running.\n'
  fi
}
