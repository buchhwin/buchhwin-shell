#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib/hypr.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/hypr.sh"
# shellcheck source=lib/nested-guard.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib/nested-guard.sh"

# A nested test session must never suspend, reboot or power off the host. The
# flag alone was the guard, and the flag is exactly what the testing recipe
# does not export: it hands you the nested WAYLAND_DISPLAY, signature and XDG
# dirs. `nested_environment` recognises that session by its files as well, and
# once recognised the whole script behaves as nested - the lock unit and its
# directory get the -nested names, the Plasma restore is skipped, and the
# helpers this script starts (apptheme-restore.py, lock.qml) inherit the flag.
if nested_environment; then
  export BUCHHWIN_NESTED=1
fi
if [[ ${BUCHHWIN_NESTED:-0} == 1 && ${1:-} =~ ^(suspend|reboot|poweroff)$ ]]; then
  printf 'session-action: %s skipped in a nested test session\n' "$1" >&2
  exit 0
fi

project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)

# ActiveState of the lock unit: inactive, active, activating, deactivating or
# failed (empty when systemctl cannot answer).
unit_state() {
  systemctl --user show -p ActiveState --value "$1" 2>/dev/null
}

# The lock screen (lock.qml) runs as its own Quickshell process in a transient
# systemd unit: a shell restart cannot kill it, a crash restarts it and the
# compositor keeps the session locked meanwhile (misc:allow_session_lock_restore).
# The blurred backdrops are made before the screen is locked. Returns once the
# session is locked (swayidle -w waits for that before sleeping).
lock_session() {
  local unit=buchhwin-shell-lock
  [[ ${BUCHHWIN_NESTED:-0} == 1 ]] && unit=buchhwin-shell-lock-nested
  # Idle, lid, before-sleep and the hotkey can all ask to lock; keep one locker.
  # `is-active` is not enough. A unit that is still coming up or going down is
  # not active, but systemd-run refuses its name all the same ("Unit ... was
  # already loaded or has a fragment file") - and the fallback below then
  # stopped the lock screen that was on its way up.
  case "$(unit_state "$unit")" in
    active | activating | reloading) exit 0 ;;
    deactivating)
      # The previous locker is leaving; wait for its name to come free.
      for _ in {1..40}; do
        [[ $(unit_state "$unit") == deactivating ]] || break
        sleep 0.05
      done
      ;;
  esac
  pgrep -u "$(id -u)" -x swaylock >/dev/null && exit 0

  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/buchhwin-shell/lock"
  [[ ${BUCHHWIN_NESTED:-0} == 1 ]] && dir="$dir-nested"
  install -d -m 700 -- "$dir"
  rm -f -- "$dir"/*.png "$dir/locked"
  python3 "$project_dir/scripts/lock-backdrop.py" capture "$dir" >/dev/null 2>&1 || true

  local env_args=()
  local name
  for name in WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME \
      BUCHHWIN_NESTED BUCHHWIN_LOCK_PAM_SERVICE BUCHHWIN_LOCK_LID_CLOSED BUCHHWIN_SHELL_PATH QT_QPA_PLATFORMTHEME; do
    [[ -n ${!name:-} ]] && env_args+=("--setenv=$name=${!name}")
  done
  systemctl --user reset-failed "$unit" 2>/dev/null || true
  # RestartSec is the width of the black gap a crashed lock screen leaves on
  # screen, so it is as short as systemd allows to be useful.
  local owner=none
  if systemd-run --user --quiet --collect --unit="$unit" --description="buchhwin-shell lock screen" \
      -p Restart=on-failure -p RestartSec=100ms "${env_args[@]}" "--setenv=BUCHHWIN_LOCK_DIR=$dir" \
      quickshell --no-duplicate -p "$project_dir/lock.qml"; then
    owner=mine
  elif [[ $(unit_state "$unit") == active || $(unit_state "$unit") == activating ]]; then
    # Someone else took the name in the moment between the guard and this line.
    owner=theirs
  fi
  if [[ $owner != none ]]; then
    for _ in {1..60}; do
      [[ -e $dir/locked ]] && exit 0
      sleep 0.05
    done
  fi
  # Another locker's screen is not ours to stop, however long it takes to come
  # up: stopping it is the one outcome this function must never produce.
  [[ $owner == theirs ]] && exit 0

  # The lock screen did not come up: never leave the session unlocked.
  systemctl --user stop "$unit" 2>/dev/null || true
  if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
    printf 'session-action: lock screen did not start\n' >&2
    exit 1
  fi
  exec swaylock -f -c 111318
}

case "${1:-}" in
  logout)
    # Settings > Appearance "Apps follow theme" / "Use the shell accent in
    # apps": give Plasma its colours back (only when the shell changed them and
    # the restore option is on).
    if [[ ${BUCHHWIN_NESTED:-0} != 1 ]]; then
      timeout 30 python3 "$project_dir/scripts/apptheme-restore.py" || true
    fi
    hypr_dispatch exit 'hl.dsp.exit()'
    ;;
  lock)
    lock_session
    ;;
  suspend)
    systemctl suspend
    ;;
  reboot)
    systemctl reboot
    ;;
  poweroff)
    systemctl poweroff
    ;;
  *)
    printf 'Usage: %s {logout|lock|suspend|reboot|poweroff}\n' "$0" >&2
    exit 2
    ;;
esac
