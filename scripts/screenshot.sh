#!/usr/bin/env bash
set -euo pipefail

# Screenshots for buchhwin-shell: saved to ~/Pictures/Screenshots, copied to
# the clipboard and announced with a notification offering to edit (swappy)
# or open the folder.
#   screenshot.sh region | screen | window
# A nested test session keeps its screenshots in its own state directory: the
# user's Pictures folder is the host's, and a test must not fill it.
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
# shellcheck source=lib/nested-guard.sh
source "$here/lib/nested-guard.sh"
mode=${1:-region}
# One screenshot at a time: Super+S (or Print) pressed again while the
# selection is up stacked another selection overlay on top of it, as often as
# it was pressed (15.10.). A second press now does nothing. The lock is this
# script's open file and goes with it; the notification below lets it go
# before it waits for an answer, so the next screenshot never waits on it.
lock_file="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-screenshot.lock"
exec 9>"$lock_file"
flock -n 9 || exit 0
if nested_environment; then
  target_dir="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/screenshots"
else
  pictures=$(xdg-user-dir PICTURES 2>/dev/null || printf '%s/Pictures' "$HOME")
  target_dir="$pictures/Screenshots"
fi
mkdir -p -- "$target_dir"
file="$target_dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
# Two shots in the same second: the second gets a number instead of
# replacing the first.
n=2
while [[ -e $file ]]; do
  file="$target_dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S)-$n.png"
  n=$(( n + 1 ))
done

case "$mode" in
  region)
    # A cancelled selection is not an error.
    geometry=$(slurp -d -b '#00000066' -c '#4f8ff7' -w 2) || exit 0
    grim -g "$geometry" "$file"
    ;;
  screen)
    output=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')
    grim -o "$output" "$file"
    ;;
  window)
    geometry=$(hyprctl -j activewindow | jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')
    [[ -n $geometry ]] || exit 0
    grim -g "$geometry" "$file"
    ;;
  *)
    printf 'Usage: %s {region|screen|window}\n' "$0" >&2
    exit 2
    ;;
esac

# Not handed to wl-copy: it stays behind to serve the clipboard and would
# hold the lock until something else is copied.
wl-copy --type image/png < "$file" 9>&-
# The picture is taken: the next one may start now.
exec 9>&-

# Actions are handled in the background so the key binding returns at once.
# notify-send waits until its notice closes, and the shell keeps notices in
# its history: unbounded, every screenshot left this subshell and its
# notify-send behind for good (15.10.). Ten minutes is time enough to click;
# after that the notice stays in the history and its buttons do nothing.
#
# The editor is an application, and this script also runs from the shell (the
# launcher's "Screenshot: …"), whose environment is the shell's own
# (scripts/lib/app-env.sh): swappy goes through launch-app.sh for the
# session's environment and a unit of its own, like everything the launcher
# starts. The folder already does: xdg-open is the session's
# (session/bin/xdg-open, first on PATH), which ends in launch-app.sh too.
(
  action=$(timeout 10m notify-send --app-name=Screenshot --icon="$file" \
    --action=edit=Edit --action=folder="Open folder" \
    "Screenshot saved" "Copied to the clipboard · ${file##*/}" 2>/dev/null || true)
  case "$action" in
    edit) "$here/launch-app.sh" swappy swappy -f "$file" ;;
    folder) xdg-open "$target_dir" ;;
  esac
) >/dev/null 2>&1 &
disown
