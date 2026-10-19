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
# failed (empty when systemctl cannot answer). Never a failure itself: read
# into a variable, one would end this `set -e` script before its fallback.
unit_state() {
  systemctl --user show -p ActiveState --value "$1" 2>/dev/null || true
}

# Waits up to 3 s for the lock screen's marker in $2 (`locked`, written once
# the session is locked). 0: it is there. 1: the unit $1 failed, ended or is
# going away, so no marker will come; its state is read every 250 ms, not
# every 50, and an empty answer (systemctl cannot say) keeps waiting.
# 2: the time is up. No longer than 3 s: a before-sleep lock holds logind's
# suspend through this call (swayidle -w), and logind waits 5 s at most
# (InhibitDelayMaxUSec), the backdrop capture before it included.
await_lock() {
  local unit=$1 dir=$2 i
  for i in {1..60}; do
    [[ -e $dir/locked ]] && return 0
    if (( i % 5 == 1 )); then
      case "$(unit_state "$unit")" in
        failed | inactive | deactivating) return 1 ;;
      esac
    fi
    sleep 0.05
  done
  return 2
}

# The lock screen (lock.qml) runs as its own Quickshell process in a transient
# systemd unit: a shell restart cannot kill it, a crash restarts it and the
# compositor keeps the session locked meanwhile (misc:allow_session_lock_restore).
# The blurred backdrops are made before the screen is locked. Returns once the
# session is locked (swayidle -w waits for that before sleeping).
lock_session() {
  local unit=buchhwin-shell-lock
  [[ ${BUCHHWIN_NESTED:-0} == 1 ]] && unit=buchhwin-shell-lock-nested
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/buchhwin-shell/lock"
  [[ ${BUCHHWIN_NESTED:-0} == 1 ]] && dir="$dir-nested"
  # Idle, lid, before-sleep and the hotkey can all ask to lock; keep one locker.
  # `is-active` is not enough. A unit that is still coming up or going down is
  # not active, but systemd-run refuses its name all the same ("Unit ... was
  # already loaded or has a fragment file") - and the fallback below then
  # stopped the lock screen that was on its way up.
  local state waited
  state=$(unit_state "$unit")
  if [[ $state == active || $state == activating || $state == reloading ]]; then
    # Another caller's lock screen. Returning tells swayidle -w that the
    # session is locked, and logind suspends then - but a Type=simple unit is
    # active as soon as it forks, ~1.2 s before the session is locked, and a
    # suspend asked for in that moment went through with the desktop open.
    # So its marker is waited for, as our own would be. One that ends
    # meanwhile (the tail of an unlock) is replaced below; one that is still
    # on its way up afterwards is never stopped.
    waited=0
    await_lock "$unit" "$dir" || waited=$?
    (( waited == 1 )) || exit 0
    state=$(unit_state "$unit")
  fi
  if [[ $state == deactivating ]]; then
    # The previous locker is leaving; wait for its name to come free.
    for _ in {1..40}; do
      [[ $(unit_state "$unit") == deactivating ]] || break
      sleep 0.05
    done
  fi
  pgrep -u "$(id -u)" -x swaylock >/dev/null && exit 0

  install -d -m 700 -- "$dir"
  rm -f -- "$dir"/*.png "$dir/locked"
  python3 "$project_dir/scripts/lock-backdrop.py" capture "$dir" >/dev/null 2>&1 || true

  # The lock's quickshell runs with the shell's own process settings
  # (start-shell.sh has the measurements and the reasons), not with the user
  # manager's environment the unit starts from: no KDE platform theme - the
  # manager's QT_QPA_PLATFORMTHEME=kde loaded KConfig, KIconThemes and
  # KColorScheme into a face that draws with its own fonts and colours and no
  # theme icons (8 MB of resident memory, offscreen) -, two allocator arenas,
  # no Mesa glthread or Gallium thread and no decoration context per lock
  # surface. An exported value wins, as there.
  local unset_args=(-u QT_QPA_PLATFORMTHEME)
  local settings=("MALLOC_ARENA_MAX=${MALLOC_ARENA_MAX:-2}"
    "MALLOC_CONF=${MALLOC_CONF:-narenas:2,background_thread:true,dirty_decay_ms:1000}"
    "mesa_glthread=${mesa_glthread:-false}" "GALLIUM_THREAD=${GALLIUM_THREAD:-0}"
    "QT_WAYLAND_DISABLE_WINDOWDECORATION=${QT_WAYLAND_DISABLE_WINDOWDECORATION:-1}")
  local names=(WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME
    BUCHHWIN_NESTED BUCHHWIN_SHELL_PATH)
  # The lock's test hooks - a PAM fixture in place of the real service, the
  # lid override - reach it only from a nested session its files confirm
  # (nested-guard.sh), never on BUCHHWIN_NESTED=1 alone: a flag left in a
  # terminal can reach a real session's shell, and a lock on test-permit
  # takes any password. Otherwise they are taken out of the unit's
  # environment, the user manager's included. The preview (windows in place
  # of the session lock) is for a lock started by hand, never for one this
  # script waits for.
  unset_args+=(-u BUCHHWIN_LOCK_PREVIEW)
  if (unset BUCHHWIN_NESTED; nested_environment); then
    names+=(BUCHHWIN_LOCK_PAM_SERVICE BUCHHWIN_LOCK_LID_CLOSED)
  else
    unset_args+=(-u BUCHHWIN_LOCK_PAM_SERVICE -u BUCHHWIN_LOCK_LID_CLOSED)
  fi
  local env_args=()
  local name
  for name in "${names[@]}"; do
    [[ -n ${!name:-} ]] && env_args+=("--setenv=$name=${!name}")
  done
  # Found here, as systemd-run would have: env looks in the unit's PATH,
  # which is the user manager's.
  local quickshell_bin
  quickshell_bin=$(command -v quickshell) || quickshell_bin=quickshell
  systemctl --user reset-failed "$unit" 2>/dev/null || true
  # RestartSec is the width of the black gap a crashed lock screen leaves on
  # screen, so it is as short as systemd allows to be useful.
  local owner=none
  if systemd-run --user --quiet --collect --unit="$unit" --description="buchhwin-shell lock screen" \
      -p Restart=on-failure -p RestartSec=100ms "${env_args[@]}" "--setenv=BUCHHWIN_LOCK_DIR=$dir" \
      env "${unset_args[@]}" "${settings[@]}" "$quickshell_bin" --no-duplicate -p "$project_dir/lock.qml"; then
    owner=mine
  elif [[ $(unit_state "$unit") == active || $(unit_state "$unit") == activating ]]; then
    # Someone else took the name in the moment between the guard and this line.
    owner=theirs
  fi
  # Ours that failed or ended on its way up (a crash loop that ran out of
  # restarts) writes no marker: the fallback comes at once, not after 3 s.
  if [[ $owner != none ]]; then
    await_lock "$unit" "$dir" && exit 0
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
