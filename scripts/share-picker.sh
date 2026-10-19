#!/usr/bin/env bash
# The share picker xdg-desktop-portal-hyprland runs when an app asks to share
# the screen, once ~/.config/hypr/xdph.conf names it:
#
#   screencopy {
#       custom_picker_binary = /home/<you>/.local/share/buchhwin-shell/scripts/share-picker.sh
#   }
#
# (then `systemctl --user restart xdg-desktop-portal-hyprland`). It asks the
# running shell, which shows its own picker with live previews of the
# screens and windows on the focused screen, and hands on what was chosen.
# Settings > Desktop extras > Screen sharing shows the lines and whether the
# portal uses them.
#
# The contract (services/sharepicker/SharePickerLogic.js has it in full): the
# portal waits for this to exit and reads one line from its stdout,
#   [SELECTION]<flags>/screen:<output> | window:<handle> | region:<output>@x,y,w,h
# and a run without one is a cancelled share. The portal never gives up
# waiting, so this does: a shell that is not there, does not take the
# request within five seconds, refuses it (Settings switched it off), dies
# while its picker is open or answers something that is not a choice
# ("fallback": its picker did not come up) hands over to the portal's own
# hyprland-share-picker, with the same arguments. A picker left open for
# BUCHHWIN_SHARE_PICKER_TIMEOUT seconds (120) is closed and the share
# cancelled - the user walked away, and another picker would only wait for
# them in the same way.
#
# The portal's window list (XDPH_WINDOW_SHARING_LIST: titles) goes to the
# shell in a file of a private directory, never as an argument, which every
# user of the machine can read; the shell answers with one line on a FIFO
# there. A region is asked of slurp here, once the shell's picker is gone.
set -uo pipefail

args=("$@")
allow=false
for arg in "$@"; do
  if [[ $arg == --allow-token ]]; then allow=true; fi
done
limit=${BUCHHWIN_SHARE_PICKER_TIMEOUT:-120}
if ! [[ $limit =~ ^[0-9]+$ ]] || (( limit < 1 )); then limit=120; fi

# The running shell, found the way scripts/buchhwin finds it.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
if [[ -n ${BUCHHWIN_SHELL_PATH:-} ]]; then
  shell_path=$BUCHHWIN_SHELL_PATH
elif [[ -e "$installed_dir/shell.qml" ]]; then
  shell_path=$installed_dir
else
  shell_path=$project_dir
fi

# What the portal reads as a choice, the same expression as
# SharePickerLogic.validSelection. Nothing else is ever printed.
selection_re='^\[SELECTION\]r?/(screen:[A-Za-z0-9._-]{1,64}|window:[0-9]{1,10}|region:[A-Za-z0-9._-]{1,64}@-?[0-9]{1,6},-?[0-9]{1,6},[0-9]{1,6},[0-9]{1,6})$'

dir=""
cleanup() {
  if [[ -n $dir ]]; then rm -rf -- "$dir"; fi
  dir=""
}
trap cleanup EXIT

# The portal's own picker, as the portal would have run it. exec skips the
# EXIT trap, so the request's directory goes first. Its stderr stays the
# portal's (the journal); closing a descriptor that is not open is no error.
fallback() {
  cleanup
  exec 9>&-
  local picker
  picker=$(command -v hyprland-share-picker 2>/dev/null) || exit 1
  exec "$picker" "${args[@]}"
}

command -v quickshell >/dev/null 2>&1 || fallback

# The shell's instance and its process: the request goes to it alone, and
# the wait below watches it. Captured, not piped (testing.md pitfall 15).
listing=$(timeout 3 quickshell list --json --path "$shell_path" 2>/dev/null) || fallback
if [[ $listing =~ \"pid\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  pid=${BASH_REMATCH[1]}
else
  fallback
fi

# The request's directory: under the shell's runtime directory, the user's
# alone. The shell writes its answer only into a directory of this shape
# (SharePickerLogic.requestDirOk).
umask 077
base="${XDG_RUNTIME_DIR:-/tmp}/buchhwin-shell/share-picker"
mkdir -p -- "$base" 2>/dev/null || fallback
dir=$(mktemp -d -- "$base/req.XXXXXXXX" 2>/dev/null) || fallback
printf '%s' "${XDPH_WINDOW_SHARING_LIST:-}" > "$dir/windows" || fallback
# Opened for reading and writing, so neither this open nor the shell's write
# waits for the other; `read -t` below then waits without a process per turn.
mkfifo -m 600 -- "$dir/answer" 2>/dev/null || fallback
exec 9<>"$dir/answer" || fallback

reply=$(timeout 5 quickshell ipc --pid "$pid" call sharePicker request "$dir" "$allow" 2>/dev/null) || fallback
[[ $reply == opened ]] || fallback

deadline=$((SECONDS + limit))
answer=""
while :; do
  IFS= read -r -t 1 -u 9 answer && break
  status=$?
  # Not a timeout: the FIFO went away under us.
  if (( status <= 128 )); then fallback; fi
  if [[ ! -d /proc/$pid ]]; then fallback; fi
  if (( SECONDS >= deadline )); then
    timeout 5 quickshell ipc --pid "$pid" call sharePicker cancel "$dir" >/dev/null 2>&1
    exit 1
  fi
done

case $answer in
  cancel)
    exit 1
    ;;
  "[SELECTION]"*)
    if [[ $answer =~ $selection_re ]]; then
      printf '%s\n' "$answer"
      exit 0
    fi
    fallback
    ;;
  region | "region r")
    flags=""
    if [[ $answer == "region r" ]]; then flags=r; fi
    command -v slurp >/dev/null 2>&1 || fallback
    # The look of the screenshot's selection (scripts/screenshot.sh); the
    # place is the output's own (%X, %Y), as the portal wants it, cropped to
    # that output. Escape in slurp cancels the share.
    region=$(slurp -d -b '#00000066' -c '#4f8ff7' -w 2 -f '%o@%X,%Y,%W,%H' </dev/null 2>/dev/null) || exit 1
    line="[SELECTION]$flags/region:$region"
    [[ $line =~ $selection_re ]] || fallback
    # A click without a drag is no region to share.
    [[ $region =~ ,([0-9]+),([0-9]+)$ ]] || fallback
    if (( 10#${BASH_REMATCH[1]} == 0 || 10#${BASH_REMATCH[2]} == 0 )); then exit 1; fi
    printf '%s\n' "$line"
    exit 0
    ;;
esac
fallback
