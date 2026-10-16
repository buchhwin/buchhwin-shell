#!/usr/bin/env bash
set -euo pipefail

# Load the shell and verify IPC targets and log cleanliness.
#   scripts/smoke-session.sh            reload the shell in the current session
#   scripts/smoke-session.sh --nested   use a disposable nested Hyprland
#   BUCHHWIN_SMOKE_KEEP=1               keep the nested session running
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/hyprland-prefix.sh
if [[ -r "$project_dir/scripts/lib/hyprland-prefix.sh" ]]; then source "$project_dir/scripts/lib/hyprland-prefix.sh"; fi
# Every IpcHandler target shell.qml declares, in its order; only `show` is
# read, nothing is called. tests/python/smoke_targets_test.py holds this list
# to shell.qml in both directions.
expected_targets=(desktop editor welcome emoji launcher controlCenter notifications powerMenu settings appTheme dashboard popup weather calendar network bluetooth kdeConnect fingerprint drives accounts updates recording shortcuts nightLight focus overview gestures colorPicker wallpaperPicker switcher clipboard brightness workspaces kbdBacklight power displays bar notch timer audio mode profile dock startMenu)
[[ -n ${BUCHHWIN_EXPECTED_TARGETS:-} ]] && read -r -a expected_targets <<<"$BUCHHWIN_EXPECTED_TARGETS"

# Warnings from the environment or Quickshell itself rather than from this shell:
# malformed desktop entries (swappy's Exec line), Plasma owning the notification
# name in nested tests, PipeWire nodes without a channel map, the KDE calendar
# plugin reading an empty settings key ("QSettings::value: Empty key passed":
# KF6XmlGui's language override, KDEPrivate::initializeLanguages, which runs
# once org.kde.akonadi is imported - CalendarService.qml - and loads
# libKPim6AkonadiWidgets, which loads libKF6XmlGui), a running playerctld without players
# (its MPRIS proxy answers with errors), Quickshell's own Wrapper* types
# overriding implicitWidth (qt.qml.propertyCache.append), installed icons
# Qt's SVG reader cannot parse (qt.svg; btop's, once the launcher opens), and
# Qt 6.12's text-input plugin (Arch) noting that a field gave up a focus no
# surface had any more, or that one surface's field asked for the text input
# while another surface still held it - the start menu's search field handing
# over to the dock's menu and the welcome tour does that (round 12). Only
# those two messages, not the category.
known_warnings='quickshell\.desktopentry|Could not register notification server|Registration will be attempted again|channelVolumes and channelMap are not the same size|QSettings::value: Empty key passed|playerctld|qt\.qml\.propertyCache\.append|qt\.svg: |QWaylandTextInputv3::disableSurface.*but 0x0 is focused|QWaylandTextInputv3::(enable|disable)Surface.*Trying to (enable|disable) 0x[0-9a-f]+ but 0x[0-9a-f]+ (has focus|is focused)'

if [[ ${1:-} == --nested ]]; then
  # The trap comes first: a start that fails half-way (set -e ends this script
  # at once) has already written hyprland.pid, and `stop` reads that file.
  [[ ${BUCHHWIN_SMOKE_KEEP:-0} == 1 ]] || trap '"$project_dir/scripts/nested-session.sh" stop' EXIT
  env_lines=$("$project_dir/scripts/nested-session.sh" start "${BUCHHWIN_SMOKE_SIZE:-1920x1200}" "${BUCHHWIN_SMOKE_SCALE:-1}")
  base=$(sed -n 's/^NESTED_DIR=//p' <<<"$env_lines")
  export HYPRLAND_INSTANCE_SIGNATURE=$(sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' <<<"$env_lines")
  export WAYLAND_DISPLAY=$(sed -n 's/^NESTED_WAYLAND_DISPLAY=//p' <<<"$env_lines")
  export XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/state" XDG_CACHE_HOME="$base/cache"
  config_path=$project_dir
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
# A step this machine cannot run (the pointer tool without its build tools)
# is a skip, not a pass: the script exits 77 for it when nothing failed, and
# scripts/test.sh names it in its summary.
skipped=0
targets=$(quickshell ipc --path "$config_path" show)
for target in "${expected_targets[@]}"; do
  if grep -q "^target $target\$" <<<"$targets"; then
    printf 'ok       ipc target %s\n' "$target"
  else
    printf 'missing  ipc target %s\n' "$target"
    status=1
  fi
done

# The dashboard opens (nested only). It used to switch between three calendar
# views here; it always shows the month now, so what is left to check is that it
# opens at all - the log check below catches errors in its month grid.
if [[ ${1:-} == --nested ]]; then
  quickshell ipc --path "$config_path" call dashboard open >/dev/null
  opened=""
  for _ in {1..20}; do
    opened=$(quickshell ipc --path "$config_path" call popup get)
    [[ $opened == dashboard ]] && break
    sleep 0.1
  done
  quickshell ipc --path "$config_path" call dashboard close >/dev/null
  if [[ $opened == dashboard ]]; then
    printf 'ok       the dashboard opens\n'
  else
    printf 'failed   the dashboard did not open (popup get: %s)\n' "$opened"
    status=1
  fi
fi

# Pointer injection (nested only, BUCHHWIN_SMOKE_POINTER=0 skips): the virtual
# pointer lands on BUCHTEST's logical coordinates and a click outside an open
# panel closes it.
if [[ ${1:-} == --nested && ${BUCHHWIN_SMOKE_POINTER:-1} == 1 ]]; then
  if ! "$project_dir/scripts/nested-pointer" --build 2>/dev/null; then
    printf 'skip     pointer (tool cannot build)\n'
    skipped=1
  else
    export BUCHHWIN_NESTED_DIR=$base
    monitor=$(hyprctl -j monitors | jq -c '.[] | select(.name == "BUCHTEST")')
    monitor_x=$(jq '.x' <<<"$monitor") monitor_y=$(jq '.y' <<<"$monitor")
    expected="$(( monitor_x + 200 )),$(( monitor_y + 150 ))"
    bottom=$(jq '.height / .scale | floor - 20' <<<"$monitor")
    # Poll instead of fixed sleeps: under load (parallel nested sessions) the
    # open and close transitions can take longer than a few hundred ms.
    popup_state() { quickshell ipc --path "$config_path" call popup get; }
    popup_closed() {
      local state
      state=$(popup_state)
      for _ in {1..20}; do
        [[ -z $state ]] && break
        sleep 0.1
        state=$(popup_state)
      done
      printf '%s' "$state"
    }
    cursor_now() { hyprctl -j cursorpos 2>/dev/null | jq -r '"\(.x | floor),\(.y | floor)"' 2>/dev/null || true; }

    # The pointer steps failed two deploys of round 12 with the cursor at
    # 960,600 - the exact centre of the nested window's output, as in both
    # failures of pitfall 41: something warped it there, a hand would have
    # left it anywhere. Two things do that. The nested shell moves the
    # misplaced workspaces of its fresh two-output session right after its
    # start (HyprlandService.applyWorkspaceRules, rounds 400 ms apart), and
    # each focusmonitor of those warps the cursor to that monitor's centre;
    # and the host can warp its own pointer into the middle of the nested
    # window when that window gets the focus. So the pointer steps wait for
    # the workspaces and monitors to stay the same for a second first, every
    # move is read back and tried again (up to three times, each reading
    # kept for the output), and a click is pressed only on a cursor that was
    # read where it was sent.
    compositor_settled() {
      local last="" now same=0
      for _ in {1..50}; do
        now=$( { hyprctl -j workspaces | jq -c '[.[] | {id, monitor}] | sort_by(.id)'
                 hyprctl -j monitors | jq -c '[.[] | {name, focused, workspace: .activeWorkspace.id}]'; } 2>/dev/null ) || now=""
        if [[ -n $now && $now == "$last" ]]; then
          same=$(( same + 1 ))
          (( same >= 5 )) && return 0
        else
          same=0 last=$now
        fi
        sleep 0.2
      done
      return 1
    }
    # pointer_at X Y: there on BUCHTEST, moved twice a few pixels apart (a
    # surface under a still pointer gets no enter, pitfall 56) and read back.
    # The readings go to $pointer_readings.
    pointer_at() {
      local want="$(( monitor_x + $1 )),$(( monitor_y + $2 ))" got
      pointer_readings=""
      for _ in 1 2 3; do
        "$project_dir/scripts/nested-pointer" move "$(( $1 + 4 ))" "$(( $2 + 4 ))" sleep 40 move "$1" "$2" >/dev/null 2>&1 || true
        sleep 0.05
        got=$(cursor_now)
        pointer_readings+="${pointer_readings:+ }${got:-?}"
        [[ $got == "$want" ]] && return 0
        sleep 0.3
      done
      return 1
    }
    # click_away X Y: a click at X Y on BUCHTEST that should close the open
    # panel. Pressed only once the cursor was read there; tried a second time
    # only when the cursor was not where it was pressed afterwards either (a
    # warp, not the panel's answer) or never got there. The panel's state just
    # before the first press is $before_press, the one after the last try
    # $closed, and what the cursor did is $click_readings.
    click_away() {
      local want="$(( monitor_x + $1 )),$(( monitor_y + $2 ))" after try pressed=0
      click_readings="" before_press="" closed=""
      for try in 1 2; do
        if ! pointer_at "$1" "$2"; then
          click_readings+="${click_readings:+; }try $try: cursor at $pointer_readings, not pressed"
          closed=$(popup_state)
          continue
        fi
        if (( ! pressed )); then before_press=$(popup_state); pressed=1; fi
        "$project_dir/scripts/nested-pointer" click "$1" "$2" >/dev/null 2>&1 || true
        closed=$(popup_closed)
        after=$(cursor_now)
        click_readings+="${click_readings:+; }try $try: cursor at $pointer_readings, after the click ${after:-?}"
        [[ -z $closed ]] && return 0
        [[ $after == "$want" ]] && return 1
      done
      [[ -z $closed ]]
    }

    if ! compositor_settled; then
      printf 'note     the workspaces and monitors were still changing after 10 s; going on\n'
    fi
    if pointer_at 200 150; then
      if [[ $pointer_readings == *' '* ]]; then
        printf 'ok       pointer moves to output coordinates (readings: %s)\n' "$pointer_readings"
      else
        printf 'ok       pointer moves to output coordinates\n'
      fi
    else
      printf 'failed   pointer move: cursor at %s (one reading per try), expected %s\n' "$pointer_readings" "$expected"
      status=1
    fi
    quickshell ipc --path "$config_path" call dashboard open >/dev/null
    active=""
    for _ in {1..20}; do
      active=$(popup_state)
      [[ $active == dashboard ]] && break
      sleep 0.1
    done
    sleep 0.3
    click_away 20 "$bottom" || true
    if [[ $active == dashboard && -z $closed ]]; then
      printf 'ok       pointer click outside closes the dashboard\n'
    else
      printf 'failed   pointer click outside the dashboard (open: %s, after: %s; %s)\n' \
        "${active:-none}" "${closed:-none}" "$click_readings"
      status=1
      [[ -n $closed ]] && quickshell ipc --path "$config_path" call popup close >/dev/null 2>&1 || true
    fi
    # A click on another monitor closes it too (cd1e136). The scrim covers
    # only the panel's own screen, so that is HyprlandFocusGrab's doing, and
    # Hyprland ignores the grab of a layer with exclusive keyboard focus
    # (testing.md, pitfall 83) - a change back to Exclusive passed the click
    # above. The virtual pointer only reaches BUCHTEST, so the dashboard opens
    # on the nested window's own output and the click lands on BUCHTEST, away
    # from both its card and its scrim.
    other=$(hyprctl -j monitors | jq -r '[.[] | select(.name != "BUCHTEST") | .name][0] // empty')
    if [[ -z $other ]]; then
      printf 'failed   no second output for the click on another monitor\n'
      status=1
    else
      # Both dialects, as for the keys below; each ignores the other's line.
      hyprctl dispatch focusmonitor "$other" >/dev/null 2>&1 || true
      hyprctl dispatch "hl.dsp.focus({ monitor = \"$other\" })" >/dev/null 2>&1 || true
      for _ in {1..20}; do
        [[ $(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name') == "$other" ]] && break
        sleep 0.1
      done
      quickshell ipc --path "$config_path" call dashboard open >/dev/null
      active=""
      for _ in {1..20}; do
        active=$(popup_state)
        [[ $active == dashboard ]] && break
        sleep 0.1
      done
      # Where it opened, from the compositor's layer list: on BUCHTEST the
      # click below would land on its own scrim and prove nothing.
      panel_output=$(hyprctl -j layers | jq -r '[to_entries[] | select([.value.levels[][]?.namespace] | index("buchhwin-dashboard")) | .key][0] // empty')
      sleep 0.3
      # The focusmonitor above warped the cursor to the centre of $other;
      # click_away moves it onto BUCHTEST and reads it back before it presses.
      click_away 200 150 || true
      if [[ $active == dashboard && $panel_output == "$other" && $before_press == dashboard && -z $closed ]]; then
        printf 'ok       a click on another monitor closes the dashboard\n'
      else
        printf 'failed   click on another monitor (open: %s on %s, before the click: %s, after: %s; %s)\n' \
          "${active:-none}" "${panel_output:-?}" "${before_press:-none}" "${closed:-none}" "$click_readings"
        status=1
        [[ -n $closed ]] && quickshell ipc --path "$config_path" call dashboard close >/dev/null 2>&1 || true
      fi
    fi
    # A key: Super+D through Hyprland's bind - a global shortcut in the Lua
    # dialect, the IPC client in the conf one - opens the launcher, and
    # Escape closes it again.
    if "$project_dir/scripts/nested-keys" --build 2>/dev/null; then
      hyprctl dispatch focusmonitor BUCHTEST >/dev/null 2>&1 || true
      hyprctl dispatch 'hl.dsp.focus({ monitor = "BUCHTEST" })' >/dev/null 2>&1 || true
      "$project_dir/scripts/nested-keys" combo SUPER+D || true
      opened=""
      for _ in {1..20}; do
        opened=$(popup_state)
        [[ $opened == launcher ]] && break
        sleep 0.1
      done
      "$project_dir/scripts/nested-keys" combo ESCAPE || true
      shut=$(popup_state)
      for _ in {1..20}; do
        [[ -z $shut ]] && break
        sleep 0.1
        shut=$(popup_state)
      done
      if [[ $opened == launcher && -z $shut ]]; then
        printf 'ok       Super+D opens the launcher, Escape closes it\n'
      else
        printf 'failed   Super+D (open: %s, after Escape: %s)\n' "${opened:-none}" "${shut:-none}"
        status=1
      fi
    else
      printf 'skip     keys (tool cannot build)\n'
      skipped=1
    fi
    # Notch mode: hovering the notch expands it, leaving collapses it again.
    previous_mode=$(quickshell ipc --path "$config_path" call bar get | jq -r '.mode')
    quickshell ipc --path "$config_path" call bar setMode notch >/dev/null
    # Until the notch on the test output says it is there: a fixed 0.6 s was
    # usually enough and sometimes not, and a pointer that arrives before the
    # surface does hovers nothing - a failure of the test, not of the notch.
    for _ in {1..50}; do
      [[ $(quickshell ipc --path "$config_path" call notch get | jq -r '.screens.BUCHTEST.shown') == true ]] && break
      sleep 0.1
    done
    sleep 0.3
    centre=$(jq '.width / .scale / 2 | floor' <<<"$monitor")
    notch_state() { quickshell ipc --path "$config_path" call notch get | jq -r '.screens.BUCHTEST.expanded'; }
    # What it *shows*, not only that it opened. A commit once filtered the whole
    # overview away and left a black box; every step here was green, because
    # nothing looked at the contents.
    notch_rows() { quickshell ipc --path "$config_path" call notch get | jq -r '.screens.BUCHTEST.rows | length'; }
    pointer_at "$centre" 12 || true
    hover_readings=$pointer_readings
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
    pointer_at "$centre" "$bottom" || true
    leave_readings=$pointer_readings
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
      printf 'failed   notch hover (hovered: %s, after leaving: %s; cursor at %s, then %s)\n' \
        "$hovered" "$left" "$hover_readings" "$leave_readings"
      status=1
    fi
  fi
fi

# The dock and the start menu (nested only, IPC only). Neither is built while
# the dock is off - its Variants model is empty, the start menu's LazyLoader
# inactive - and the sandbox has it off, so a TypeError, a binding loop or an
# "Unable to assign" in Dock, DockZone, a dock Pill, the Saturn button, the
# apps, the start menu or the dock's menu never reached the log read below,
# while the user runs the dock (round 12, tests-docs#1). After the pointer
# steps: a taskbar along the whole bottom edge would sit under their click
# outside. Nothing in either is clicked, and the dock is off again at the end
# (a kept sandbox keeps the Taskbar's layout; the deploy's starts fresh).
if [[ ${1:-} == --nested ]]; then
  ipc_call() { quickshell ipc --path "$config_path" call "$@" 2>/dev/null || true; }
  popup_is() {
    local want=$1 state=""
    for _ in {1..30}; do
      state=$(ipc_call popup get)
      [[ $state == "$want" ]] && break
      sleep 0.1
    done
    printf '%s' "$state"
  }
  dock_ready='.enabled == true and .screens > 0 and .items > 0'
  preset=$(ipc_call dock preset taskbar)
  ipc_call dock setEnabled true >/dev/null
  dock_state=""
  for _ in {1..30}; do
    dock_state=$(ipc_call dock get)
    [[ $(jq -r "$dock_ready" <<<"$dock_state" 2>/dev/null) == true ]] && break
    sleep 0.1
  done
  if [[ $preset == true && $(jq -r "$dock_ready" <<<"$dock_state" 2>/dev/null) == true ]]; then
    printf 'ok       the dock is on with the Taskbar preset (%s)\n' \
      "$(jq -r '"\(.items) items, \(.screens) screens, shown on \(.shown)"' <<<"$dock_state")"
  else
    printf 'failed   the dock with the Taskbar preset (preset: %s, get: %s)\n' "${preset:-none}" "${dock_state:-none}"
    status=1
  fi
  # The start menu: open (out of the Saturn button on the focused screen),
  # All apps, closed again.
  ipc_call startMenu open >/dev/null
  opened=$(popup_is startMenu)
  menu_state=""
  for _ in {1..20}; do
    menu_state=$(ipc_call startMenu get)
    [[ $(jq -r '.loaded == true and .shown == true' <<<"$menu_state" 2>/dev/null) == true ]] && break
    sleep 0.1
  done
  ipc_call startMenu openView all >/dev/null
  view=""
  for _ in {1..20}; do
    view=$(ipc_call startMenu get | jq -r '.view // empty' 2>/dev/null || true)
    [[ $view == all ]] && break
    sleep 0.1
  done
  ipc_call startMenu close >/dev/null
  shut=$(popup_is "")
  if [[ $opened == startMenu && $view == all && -z $shut ]]; then
    printf 'ok       the start menu opens, shows All apps and closes\n'
  else
    printf 'failed   the start menu (open: %s, view: %s, after close: %s, get: %s)\n' \
      "${opened:-none}" "${view:-none}" "${shut:-none}" "${menu_state:-none}"
    status=1
    [[ -n $shut ]] && ipc_call popup close >/dev/null || true
  fi
  # The dock's menu for its first app, and closed again.
  menu_opened=false
  for _ in {1..30}; do
    [[ $(ipc_call dock menu 0) == true ]] && { menu_opened=true; break; }
    sleep 0.1
  done
  shown_menu=$(popup_is dockMenu)
  ipc_call popup close >/dev/null
  shut=$(popup_is "")
  if [[ $menu_opened == true && $shown_menu == dockMenu && -z $shut ]]; then
    printf 'ok       the dock menu opens and closes\n'
  else
    printf 'failed   the dock menu (menu 0: %s, popup: %s, after close: %s)\n' "$menu_opened" "${shown_menu:-none}" "${shut:-none}"
    status=1
  fi
  ipc_call dock setEnabled false >/dev/null
  for _ in {1..30}; do
    [[ $(ipc_call dock get | jq -r '.enabled' 2>/dev/null) == false ]] && break
    sleep 0.1
  done
  # The tour. A kept sandbox had never closed it, so its loader built it at
  # every start and the log read below covered it; the deploy's fresh sandbox
  # is seeded with it done (scripts/nested-session.sh, BUCHHWIN_NESTED_FRESH),
  # and then it is built only when it is opened. So it is opened, and closed.
  ipc_call welcome open >/dev/null
  welcomed=$(popup_is welcome)
  ipc_call welcome close >/dev/null
  shut=$(popup_is "")
  if [[ $welcomed == welcome && -z $shut ]]; then
    printf 'ok       the welcome tour opens and closes\n'
  else
    printf 'failed   the welcome tour (popup: %s, after close: %s)\n' "${welcomed:-none}" "${shut:-none}"
    status=1
    [[ -n $shut ]] && ipc_call popup close >/dev/null || true
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
[[ $status -eq 0 && $skipped -eq 1 ]] && exit 77
exit "$status"
