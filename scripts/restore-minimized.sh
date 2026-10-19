#!/usr/bin/env bash
set -euo pipefail

# Every minimized window back to the workspace it came from, without the
# shell. A minimized window is one on a special workspace of the shell's,
# `special:buchhwin-minimized-N` with N the workspace it goes back to (none:
# the workspace in front) - services/dock/MinimizeLogic.js. The shell lists
# them and brings them back at every start (services/MinimizeService.qml);
# this is the way back for a session whose shell is not running: Super+Shift+H
# runs it when the shell does not answer, in both dialects, and it can be run
# by hand from a TTY or a terminal.
#
#   scripts/restore-minimized.sh        prints how many came back

clients=$(hyprctl -j clients)
front=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true)
[[ $front =~ ^[1-9][0-9]*$ ]] || front=1

# address and target, one pair a line.
plan=$(jq -r --arg front "$front" '
  .[] | select((.workspace.name // "") | test("^special:buchhwin-minimized(-[1-9][0-9]*)?$"))
  | ((.workspace.name | capture("-(?<n>[1-9][0-9]*)$") | .n) // $front) as $to
  | select(.address | test("^0x[0-9a-fA-F]+$"))
  | "\(.address) \($to)"' <<<"$clients")
if [[ -z $plan ]]; then
  printf 'no minimized windows\n'
  exit 0
fi

# The dialect decides the words: `hyprctl eval` answers only a Lua
# configuration (HyprCompat.qml asks the same way).
if [[ $(hyprctl eval 'return 1' 2>/dev/null || true) == ok ]]; then
  script=""
  while read -r address to; do
    script+="hl.dispatch(hl.dsp.window.move({ workspace = $to, window = \"address:$address\", follow = false }))"$'\n'
  done <<<"$plan"
  hyprctl eval "$script" >/dev/null
else
  batch=""
  while read -r address to; do
    batch+="${batch:+ ; }dispatch movetoworkspacesilent $to,address:$address"
  done <<<"$plan"
  hyprctl --batch "$batch" >/dev/null
fi
printf '%s minimized window(s) back\n' "$(wc -l <<<"$plan" | tr -d ' ')"
