#!/usr/bin/env bash
set -euo pipefail

# Screenshots for buchhwin-shell: saved to ~/Pictures/Screenshots, copied to
# the clipboard and announced with a notification offering to edit (swappy)
# or open the folder.
#   screenshot.sh region | screen | window
# A nested test session keeps its screenshots in its own state directory: the
# user's Pictures folder is the host's, and a test must not fill it.
# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"
mode=${1:-region}
if nested_environment; then
  target_dir="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/screenshots"
else
  pictures=$(xdg-user-dir PICTURES 2>/dev/null || printf '%s/Pictures' "$HOME")
  target_dir="$pictures/Screenshots"
fi
mkdir -p -- "$target_dir"
file="$target_dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

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

wl-copy --type image/png < "$file"

# Actions are handled in the background so the key binding returns at once.
(
  action=$(notify-send --app-name=Screenshot --icon="$file" \
    --action=edit=Edit --action=folder="Open folder" \
    "Screenshot saved" "Copied to the clipboard · ${file##*/}" 2>/dev/null || true)
  case "$action" in
    edit) swappy -f "$file" ;;
    folder) xdg-open "$target_dir" ;;
  esac
) >/dev/null 2>&1 &
disown
