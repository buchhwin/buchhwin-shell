#!/usr/bin/env bash
set -euo pipefail

# Screenshots for buchhwin-shell: saved to ~/Pictures/Screenshots, copied to
# the clipboard and announced with a notification offering to edit (swappy)
# or open the folder.
#   screenshot.sh [--delay SECONDS] region | screen | window | text
# region: a drag picks a region, a click the window under the pointer.
# text: the text in a region, recognised (tesseract) and copied, no picture
# kept. --delay takes the picture that many seconds later (after the
# selection, where there is one): time to open a menu or a tooltip.
# A nested test session keeps its screenshots in its own state directory: the
# user's Pictures folder is the host's, and a test must not fill it.
# The path as it was called, resolved only when this file itself is a link
# (as in launch-default.sh).
self=${BASH_SOURCE[0]}
[[ $self == /* && ! -L $self ]] || self=$(readlink -f -- "$self")
here=${self%/*}
# shellcheck source=lib/nested-guard.sh
source "$here/lib/nested-guard.sh"
usage() {
  printf 'Usage: %s [--delay SECONDS] {region|screen|window|text}\n' "$0" >&2
  exit 2
}
# A notice through notify-send - never from a nested test session, which
# shares the user's session bus: its notices (the saved one with buttons
# that wait ten minutes) went to the live shell's notification server. There
# the summary and the text go to stderr. The last two arguments are those.
notice() {
  if nested_environment; then
    printf 'screenshot: %s - %s\n' "${@: -2:1}" "${@: -1}" >&2
    return 0
  fi
  notify-send "$@" 2>/dev/null || true
}
delay=0
if [[ ${1:-} == --delay ]]; then
  [[ ${2:-} =~ ^[0-9]{1,2}$ ]] || usage
  delay=$2
  shift 2
fi
mode=${1:-region}
case "$mode" in
  region | screen | window | text) ;;
  *) usage ;;
esac

# Text recognition needs tesseract and its English or German data (Arch
# ships only "osd" with tesseract itself). Said before anything is selected,
# with the command for this distribution (install/lib/distro.sh), never run.
ocr_languages() {
  local list wanted=()
  command -v tesseract >/dev/null 2>&1 || return 1
  list=$(tesseract --list-langs 2>/dev/null) || return 1
  grep -qx deu <<<"$list" && wanted+=(deu)
  grep -qx eng <<<"$list" && wanted+=(eng)
  (( ${#wanted[@]} )) || return 1
  local IFS=+
  printf '%s' "${wanted[*]}"
}
ocr_missing() {
  local distro="" engine=tesseract data packages
  if [[ -r $here/../install/lib/distro.sh ]]; then
    # shellcheck source=../install/lib/distro.sh
    source "$here/../install/lib/distro.sh"
    distro=$(distro_family 2>/dev/null) || distro=""
  fi
  case $distro in
    arch) data="tesseract-data-eng tesseract-data-deu" ;;
    fedora) data="tesseract-langpack-eng tesseract-langpack-deu" ;;
    opensuse-leap) engine=tesseract-ocr; data="tesseract-ocr-traineddata-english tesseract-ocr-traineddata-german" ;;
    *) data="tesseract-data-eng tesseract-data-deu" ;;
  esac
  packages=$data
  command -v tesseract >/dev/null 2>&1 || packages="$engine $data"
  notice --app-name=Screenshot --icon=dialog-information \
    "Text recognition needs language data" \
    "Install tesseract's English and German data: $(distro_hint "$distro" "$packages")"
}
distro_hint() {
  if declare -F distro_install_hint >/dev/null; then
    distro_install_hint "$1" "$2"
  else
    printf 'sudo pacman -S %s' "$2"
  fi
}
if [[ $mode == text ]]; then
  ocr_langs=$(ocr_languages) || { ocr_missing; exit 0; }
fi

# One screenshot at a time: Super+S (or Print) pressed again while the
# selection is up stacked another selection overlay on top of it, as often as
# it was pressed (15.10.). A second press now does nothing. The lock is this
# script's open file and goes with it; the notification below lets it go
# before it waits for an answer, so the next screenshot never waits on it.
lock_file="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-screenshot.lock"
exec 9>"$lock_file"
flock -n 9 || exit 0

# The windows on screen as slurp's predefined boxes ("x,y wxh"), so a click
# picks the window under the pointer while a drag still picks a region
# (slurp takes the smallest box under the click). On screen means on a
# monitor's active workspace, or on the special workspace shown over it; not
# a window hidden in a group, not the session's hidden helpers (their
# workspace, services/hypr/HiddenWindows.js), and on a workspace with a
# fullscreen or maximized window only that one - the windows under it are
# not on screen to be clicked. Nothing at all when Hyprland does not answer:
# the region works as before. One line per box, never an empty one (slurp
# refuses the whole list over a line it cannot read).
window_boxes() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  local clients monitors
  clients=$(hyprctl -j clients 2>/dev/null) || return 0
  monitors=$(hyprctl -j monitors 2>/dev/null) || return 0
  jq -r -n --argjson clients "$clients" --argjson monitors "$monitors" '
    def covering: (.fullscreen // 0) as $f | if ($f | type) == "boolean" then $f else $f != 0 end;
    [$monitors[]? | (.activeWorkspace.id // empty), (.specialWorkspace.id // 0 | select(. != 0))] as $shown
    | [$clients[]?
       | select(.mapped != false and .hidden != true)
       | select((.workspace.name // "") != "special:buchhwin-hidden")
       | select(.workspace.id as $id | $id != null and ($shown | any(. == $id)))
       | select((.at | type) == "array" and (.size | type) == "array")
       | select(.size[0] > 0 and .size[1] > 0)] as $visible
    | [$visible[] | select(covering) | .workspace.id] as $covered
    | $visible[]
    | select(covering or (.workspace.id as $id | $covered | any(. == $id) | not))
    | "\(.at[0] | floor),\(.at[1] | floor) \(.size[0] | floor)x\(.size[1] | floor)"
  ' 2>/dev/null || true
}

# A selection, from the boxes above: printed, or nothing for a cancelled one.
select_region() {
  local boxes
  boxes=$(window_boxes)
  if [[ -n $boxes ]]; then
    printf '%s\n' "$boxes" | slurp -d -b '#00000066' -c '#4f8ff7' -w 2
  else
    slurp -d -b '#00000066' -c '#4f8ff7' -w 2 </dev/null
  fi
}

# The picture is taken this much later (--delay).
pause() {
  if (( delay > 0 )); then sleep "$delay"; fi
}

if [[ $mode == text ]]; then
  # A cancelled selection is not an error.
  geometry=$(select_region) || exit 0
  pause
  # The picture lives as long as the recognition takes, in the runtime
  # directory - it is a piece of the screen, and nothing to keep.
  shot=$(mktemp "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/buchhwin-ocr.XXXXXX.png")
  trap 'rm -f -- "$shot"' EXIT
  grim -g "$geometry" "$shot"
  # The picture is taken: the next one may start now.
  exec 9>&-
  text=$(tesseract "$shot" stdout -l "$ocr_langs" 2>/dev/null) || text=""
  # Tesseract ends a page with a form feed and blank lines.
  text=${text//$'\f'/}
  text=${text%"${text##*[![:space:]]}"}
  if [[ -z ${text//[[:space:]]/} ]]; then
    notice --app-name=Screenshot --icon=dialog-information "No text found" \
      "Nothing in the selection could be read as text"
    exit 0
  fi
  # wl-copy stays behind to serve the clipboard; it must not keep anything
  # of this script open.
  printf '%s' "$text" | wl-copy
  # The notice shows the first line read, so a wrong selection shows at once.
  first=${text#"${text%%[![:space:]]*}"}
  first=${first%%$'\n'*}
  (( ${#first} > 80 )) && first="${first:0:79}…"
  more=$(( $(grep -c . <<<"$text" || true) - 1 ))
  case $more in
    0) ;;
    1) first+=" (and 1 more line)" ;;
    *) first+=" (and $more more lines)" ;;
  esac
  notice --app-name=Screenshot --icon=edit-copy "Text copied" "$first"
  exit 0
fi

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
    geometry=$(select_region) || exit 0
    pause
    grim -g "$geometry" "$file"
    ;;
  screen)
    pause
    output=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')
    grim -o "$output" "$file"
    ;;
  window)
    pause
    geometry=$(hyprctl -j activewindow | jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end')
    [[ -n $geometry ]] || exit 0
    grim -g "$geometry" "$file"
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
if nested_environment; then
  notice "Screenshot saved" "${file##*/}"
  exit 0
fi
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
