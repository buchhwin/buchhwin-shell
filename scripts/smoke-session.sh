#!/usr/bin/env bash
set -euo pipefail

# Load the shell and verify IPC targets and log cleanliness.
#   scripts/smoke-session.sh            reload the shell in the current session
#   scripts/smoke-session.sh --nested   use a disposable nested Hyprland
#   BUCHHWIN_SMOKE_KEEP=1               keep the nested session running
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
expected_targets=(editor launcher controlCenter notifications powerMenu settings dashboard weather calendar bar notch network bluetooth displays power clipboard overview gestures focus nightLight profile)
[[ -n ${BUCHHWIN_EXPECTED_TARGETS:-} ]] && read -r -a expected_targets <<<"$BUCHHWIN_EXPECTED_TARGETS"

# Warnings from the environment or Quickshell itself rather than from this shell:
# malformed desktop entries (swappy's Exec line), Plasma owning the notification
# name in nested tests, PipeWire nodes without a channel map, the KDE calendar
# plugin reading an empty settings key, a running playerctld without players
# (its MPRIS proxy answers with errors) and Quickshell's own Wrapper* types
# overriding implicitWidth (qt.qml.propertyCache.append).
known_warnings='quickshell\.desktopentry|Could not register notification server|Registration will be attempted again|channelVolumes and channelMap are not the same size|QSettings::value: Empty key passed|playerctld|qt\.qml\.propertyCache\.append'

if [[ ${1:-} == --nested ]]; then
  env_lines=$("$project_dir/scripts/nested-session.sh" start "${BUCHHWIN_SMOKE_SIZE:-1920x1200}" "${BUCHHWIN_SMOKE_SCALE:-1}")
  base=$(sed -n 's/^NESTED_DIR=//p' <<<"$env_lines")
  export HYPRLAND_INSTANCE_SIGNATURE=$(sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' <<<"$env_lines")
  export WAYLAND_DISPLAY=$(sed -n 's/^NESTED_WAYLAND_DISPLAY=//p' <<<"$env_lines")
  export XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/state" XDG_CACHE_HOME="$base/cache"
  config_path=$project_dir
  [[ ${BUCHHWIN_SMOKE_KEEP:-0} == 1 ]] || trap '"$project_dir/scripts/nested-session.sh" stop' EXIT
else
  "$project_dir/scripts/reload-shell.sh"
  config_path="$HOME/.local/share/buchhwin-shell"
  [[ -e $config_path/shell.qml ]] || config_path=$project_dir
fi

log=""
for _ in {1..100}; do
  log=$(quickshell log --path "$config_path" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' || true)
  grep -q 'Configuration Loaded' <<<"$log" && break
  sleep 0.1
done
if ! grep -q 'Configuration Loaded' <<<"$log"; then
  printf 'Shell did not finish loading.\n%s\n' "$log" >&2
  exit 1
fi
sleep "${BUCHHWIN_SMOKE_SETTLE:-1}"
log=$(quickshell log --path "$config_path" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' || true)

status=0
targets=$(quickshell ipc --path "$config_path" show)
for target in "${expected_targets[@]}"; do
  if grep -q "^target $target\$" <<<"$targets"; then
    printf 'ok       ipc target %s\n' "$target"
  else
    printf 'missing  ipc target %s\n' "$target"
    status=1
  fi
done

# Dashboard calendar views (nested only: setView writes the settings file, and
# in the real session that is the user's). Every view must be accepted, an
# unknown one refused, and the dashboard must open in the day view (the log
# check below catches errors in its time grid).
if [[ ${1:-} == --nested ]]; then
  set_view() { quickshell ipc --path "$config_path" call dashboard setView "$1"; }
  views=""
  for view in month week day; do views+=$(set_view "$view"); done
  unknown=$(set_view hour)
  set_view day >/dev/null
  quickshell ipc --path "$config_path" call dashboard open >/dev/null
  opened=""
  for _ in {1..20}; do
    opened=$(quickshell ipc --path "$config_path" call popup get)
    [[ $opened == dashboard ]] && break
    sleep 0.1
  done
  quickshell ipc --path "$config_path" call dashboard close >/dev/null
  set_view month >/dev/null
  if [[ $views == truetruetrue && $unknown == false && $opened == dashboard ]]; then
    printf 'ok       dashboard month/week/day views\n'
  else
    printf 'failed   dashboard views (accepted: %s, unknown: %s, day view open: %s)\n' "$views" "$unknown" "$opened"
    status=1
  fi
fi

# Pointer injection (nested only, BUCHHWIN_SMOKE_POINTER=0 skips): the virtual
# pointer lands on BUCHTEST's logical coordinates and a click outside an open
# panel closes it.
if [[ ${1:-} == --nested && ${BUCHHWIN_SMOKE_POINTER:-1} == 1 ]]; then
  if ! "$project_dir/scripts/nested-pointer" --build 2>/dev/null; then
    printf 'skip     pointer (tool cannot build)\n'
  else
    export BUCHHWIN_NESTED_DIR=$base
    monitor=$(hyprctl -j monitors | jq -c '.[] | select(.name == "BUCHTEST")')
    expected="$(( $(jq '.x' <<<"$monitor") + 200 )),$(( $(jq '.y' <<<"$monitor") + 150 ))"
    bottom=$(jq '.height / .scale | floor - 20' <<<"$monitor")
    actual=""
    if "$project_dir/scripts/nested-pointer" move 200 150; then
      actual=$(hyprctl -j cursorpos | jq -r '"\(.x | floor),\(.y | floor)"')
    fi
    if [[ $actual == "$expected" ]]; then
      printf 'ok       pointer moves to output coordinates\n'
    else
      printf 'failed   pointer move: cursor at %s, expected %s\n' "${actual:-?}" "$expected"
      status=1
    fi
    # Poll instead of fixed sleeps: under load (parallel nested sessions) the
    # open and close transitions can take longer than a few hundred ms.
    popup_state() { quickshell ipc --path "$config_path" call popup get; }
    quickshell ipc --path "$config_path" call dashboard open >/dev/null
    active=""
    for _ in {1..20}; do
      active=$(popup_state)
      [[ $active == dashboard ]] && break
      sleep 0.1
    done
    sleep 0.3
    "$project_dir/scripts/nested-pointer" click 20 "$bottom" || true
    closed=$(popup_state)
    for _ in {1..20}; do
      [[ -z $closed ]] && break
      sleep 0.1
      closed=$(popup_state)
    done
    if [[ $active == dashboard && -z $closed ]]; then
      printf 'ok       pointer click outside closes the dashboard\n'
    else
      printf 'failed   pointer click outside the dashboard (open: %s)\n' "$active"
      status=1
    fi
    # Notch mode: hovering the notch expands it, leaving collapses it again.
    previous_mode=$(quickshell ipc --path "$config_path" call bar get | jq -r '.mode')
    quickshell ipc --path "$config_path" call bar setMode notch >/dev/null
    sleep 0.6
    centre=$(jq '.width / .scale / 2 | floor' <<<"$monitor")
    notch_state() { quickshell ipc --path "$config_path" call notch get | jq -r '.screens.BUCHTEST.expanded'; }
    # What it *shows*, not only that it opened. A commit once filtered the whole
    # overview away and left a black box; every step here was green, because
    # nothing looked at the contents.
    notch_rows() { quickshell ipc --path "$config_path" call notch get | jq -r '.screens.BUCHTEST.rows | length'; }
    "$project_dir/scripts/nested-pointer" move "$centre" 12 || true
    hovered=""
    for _ in {1..30}; do
      sleep 0.1
      hovered=$(notch_state)
      [[ $hovered == true ]] && break
    done
    rows=$(notch_rows)
    if [[ ${rows:-0} -gt 0 ]]; then
      printf 'ok       the expanded notch shows %s rows\n' "$rows"
    else
      printf 'failed   the expanded notch is empty (rows: %s)\n' "$rows"
      status=1
    fi
    "$project_dir/scripts/nested-pointer" move "$centre" "$bottom" || true
    left=""
    for _ in {1..30}; do
      sleep 0.1
      left=$(notch_state)
      [[ $left == false ]] && break
    done
    quickshell ipc --path "$config_path" call bar setMode "$previous_mode" >/dev/null
    if [[ $hovered == true && $left == false ]]; then
      printf 'ok       notch expands on hover and collapses after leaving\n'
    else
      printf 'failed   notch hover (hovered: %s, after leaving: %s)\n' "$hovered" "$left"
      status=1
    fi
  fi
fi

log=$(quickshell log --path "$config_path" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' || true)
problems=$(grep -E 'WARN|ERROR|CRIT|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign' <<<"$log" \
  | grep -vE "$known_warnings" || true)
if [[ -n $problems ]]; then
  printf 'Log problems:\n%s\n' "$problems"
  status=1
else
  printf 'ok       log has no shell warnings\n'
fi
exit "$status"
