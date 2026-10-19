#!/usr/bin/env bash
set -euo pipefail

# session-action.sh lock, against stub commands in a sandbox. The thing under
# test is who owns the transient unit: idle, the lid, before-sleep and the
# hotkey can all ask to lock at once, and the old guard (`systemctl is-active`)
# was blind to a unit that was still coming up - so the second caller's
# systemd-run was refused the name and the fallback then stopped the lock
# screen the first caller had just started. systemctl, systemd-run, swaylock,
# pgrep, quickshell and python3 are stubs that only record their arguments; the
# test refuses to run if PATH would reach the real systemctl.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-actiontest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL session-action: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
count="$sandbox/state-count"
mkdir -p "$bin"

# $STUB_STATES is one ActiveState per query, the last one repeating - the guard
# and the race check ask at different moments and may need different answers.
# With $STUB_SHOW_FAILS=1 the query fails as it does without a user manager.
cat > "$bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$CALLS"
state() {
  n=$(cat "$STUB_COUNT" 2>/dev/null || echo 0)
  n=$((n + 1))
  echo "$n" > "$STUB_COUNT"
  set -- ${STUB_STATES:-inactive}
  [ "$n" -gt "$#" ] && n=$#
  eval "printf '%s\\n' \"\${$n}\""
}
case "$*" in
  *"show -p ActiveState"*)
    [ "${STUB_SHOW_FAILS:-0}" = 1 ] && exit 1
    state ;;
  # The guard this test exists for used to be `is-active`, which answers yes
  # only for `active` - that is the whole bug, so the stub has to be exact.
  *is-active*) [ "$(state)" = active ] || exit 3 ;;
esac
exit 0
EOF

# Fails when $STUB_RUN_FAILS is 1 (systemd refusing a name that is still
# loaded). On success it writes the marker the real lock screen writes, so the
# caller's wait loop ends the way it would in the session - unless
# $STUB_NO_MARKER is 1: a lock screen that never gets as far.
cat > "$bin/systemd-run" <<'EOF'
#!/bin/sh
printf 'systemd-run %s\n' "$*" >> "$CALLS"
[ "${STUB_RUN_FAILS:-0}" = 1 ] && exit 1
for arg in "$@"; do
  case "$arg" in --setenv=BUCHHWIN_LOCK_DIR=*) dir=${arg#--setenv=BUCHHWIN_LOCK_DIR=} ;; esac
done
[ -n "${dir:-}" ] && [ "${STUB_NO_MARKER:-0}" != 1 ] && echo 1 > "$dir/locked"
exit 0
EOF

for name in swaylock quickshell python3; do
  cat > "$bin/$name" <<EOF
#!/bin/sh
printf '$name %s\n' "\$*" >> "\$CALLS"
exit 0
EOF
done
# No stray swaylock of the caller's.
cat > "$bin/pgrep" <<'EOF'
#!/bin/sh
exit 1
EOF

chmod +x "$bin"/*
export PATH="$bin:$PATH"
if [[ $(command -v systemctl) != "$bin/systemctl" || $(command -v systemd-run) != "$bin/systemd-run" ]]; then
  printf 'session-action test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

run="$sandbox/run"
lockdir="$run/buchhwin-shell/lock"
# The sandbox has to be the whole environment, not most of it: XDG_RUNTIME_DIR
# is where the lock directory and its marker live, and a stray BUCHHWIN_NESTED
# would rename the unit and take the swaylock fallback out of the script.
# The settings the lock unit is given, and its test hooks, come from the
# caller as well: the run starts without any of them, whoever runs the test.
# $marker_after (seconds) has another lock screen write its marker that much
# later; $elapsed is how long the call took, in milliseconds.
caller_unset=(-u BUCHHWIN_NESTED -u QT_QPA_PLATFORMTHEME -u MALLOC_ARENA_MAX -u MALLOC_CONF -u mesa_glthread
  -u GALLIUM_THREAD -u QT_WAYLAND_DISABLE_WINDOWDECORATION -u BUCHHWIN_LOCK_PAM_SERVICE -u BUCHHWIN_LOCK_LID_CLOSED
  -u BUCHHWIN_LOCK_PREVIEW)
elapsed=0
lock() {
  : > "$calls"
  : > "$count"
  rm -rf -- "$run"
  mkdir -p "$run"
  local writer="" started
  if [[ -n ${marker_after:-} ]]; then
    ( sleep "$marker_after"; mkdir -p "$lockdir"; echo 1 > "$lockdir/locked" ) &
    writer=$!
  fi
  started=$(date +%s%N)
  env "${caller_unset[@]}" BUCHHWIN_NESTED_DIR="$sandbox/no-nested" CALLS="$calls" STUB_COUNT="$count" \
    XDG_RUNTIME_DIR="$run" "$@" bash "$project_dir/scripts/session-action.sh" lock >"$sandbox/out.log" 2>&1 || true
  elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
  if [[ -n $writer ]]; then wait "$writer" 2>/dev/null || true; fi
}
# The same for the power actions, which go to (the stub) systemctl.
action() {
  : > "$calls"
  : > "$count"
  local name=$1; shift
  env -u BUCHHWIN_NESTED BUCHHWIN_NESTED_DIR="$sandbox/no-nested" CALLS="$calls" STUB_COUNT="$count" \
    XDG_RUNTIME_DIR="$run" "$@" bash "$project_dir/scripts/session-action.sh" "$name" >"$sandbox/out.log" 2>&1
}
said() { grep -q "$1" "$calls"; }
mkdir -p "$sandbox/no-nested"

# A unit that is still coming up belongs to another locker. The old guard read
# `is-active`, which is false for `activating`, and the run that followed was
# refused the name - after which the fallback stopped a lock screen that was on
# its way up. This is the regression.
lock STUB_STATES=activating
check '! said "^systemd-run"' 'a unit that is activating is left alone'
check '! said "stop"' 'a lock screen on its way up is never stopped, even when it is not up after the wait'
check '! said "^swaylock"' 'no swaylock while another locker is coming up'
check '(( elapsed >= 2500 && elapsed < 6000 ))' "another locker's screen is waited for, for 3 s and no longer (${elapsed} ms)"

marker_after=0 lock STUB_STATES=active
check '! said "^systemd-run"' 'a running lock screen is left alone'
check '(( elapsed < 1500 ))' "a lock screen that is up answers at once (${elapsed} ms)"

# A before-sleep lock that arrives while another caller's lock screen is still
# coming up returns once that screen has locked the session, not as soon as
# the unit exists: swayidle -w lets the machine suspend when it returns, and a
# Type=simple unit is active ~1.2 s before the session is locked.
marker_after=0.5 lock STUB_STATES=activating
check '(( elapsed >= 450 ))' "the call waits for the other lock screen's marker (${elapsed} ms)"
check '(( elapsed < 2500 ))' "and returns once it is there (${elapsed} ms)"
check '! said "^systemd-run" && ! said "stop" && ! said "^swaylock"' 'and leaves that lock screen alone'

# The other lock screen ends while this call waits (the tail of an unlock): it
# will not lock the session again, so this call locks it.
lock STUB_STATES="active active inactive"
check 'said "^systemd-run"' 'a lock screen that ends while it is waited for is replaced'
check '! said "^swaylock"' 'by the lock screen, not the fallback'

lock STUB_STATES="deactivating deactivating inactive"
check 'said "^systemd-run"' 'a unit on its way out is waited for, then reused'

# The ordinary case: nothing is locking, the screen comes up.
lock STUB_STATES=inactive
check 'said "^systemd-run"' 'an idle unit is started'
check 'said "RestartSec=100ms"' 'the restart gap is 100ms, not a second'
check 'said "Restart=on-failure"' 'a crashed lock screen still restarts'
check '! said "^swaylock"' 'no fallback when the lock screen came up'
check '! said "stop"' 'a lock screen that came up is not stopped'

# The name was refused and the unit is active: someone else won the race in the
# moment between the guard and the run. Their screen writes the marker shortly
# after ours would have - the wait has to end on theirs, and nothing may stop it.
: > "$calls"
: > "$count"
rm -rf -- "$run"
mkdir -p "$lockdir"
( sleep 0.3; echo 1 > "$lockdir/locked" ) &
marker_writer=$!
env -u BUCHHWIN_NESTED CALLS="$calls" STUB_COUNT="$count" XDG_RUNTIME_DIR="$run" \
  STUB_STATES="inactive active" STUB_RUN_FAILS=1 \
  bash "$project_dir/scripts/session-action.sh" lock >"$sandbox/out.log" 2>&1
wait "$marker_writer" 2>/dev/null || true
check '! said "stop"' "a refused name with someone else's lock screen up stops nothing"
check '! said "^swaylock"' 'no fallback while another lock screen is coming up'

# Nothing is up and the run failed: never leave the session unlocked.
lock STUB_STATES=inactive STUB_RUN_FAILS=1
check 'said "stop"' 'a failed start is cleaned up'
check 'said "^swaylock"' 'a failed start falls back to swaylock'
# A systemctl that cannot say what the unit is doing is no reason to stop
# short of a lock: the state is empty then, and the fallback still comes.
lock STUB_SHOW_FAILS=1 STUB_RUN_FAILS=1
check 'said "^systemd-run" && said "^swaylock"' 'without an answer from systemctl the lock is still tried, then the fallback'

# Our lock screen failed on its way up (a crash loop out of restarts; with
# --collect the unit is gone): no marker will come, and the fallback comes at
# once instead of after the whole wait.
lock STUB_STATES="inactive failed" STUB_NO_MARKER=1
check 'said "stop" && said "^swaylock"' 'a lock screen that failed on its way up falls back to swaylock'
check '(( elapsed < 1000 ))' "at once, not after 3 s (${elapsed} ms)"
lock STUB_STATES="inactive inactive" STUB_NO_MARKER=1
check 'said "^swaylock"' 'and so does one that ended'
# One that is only slow is waited for as before.
marker_after=1 lock STUB_STATES="inactive activating" STUB_NO_MARKER=1
check '! said "stop" && ! said "^swaylock"' 'a slow lock screen is not replaced while it is still starting'
check '(( elapsed >= 950 && elapsed < 2500 ))' "and the call returns with its marker (${elapsed} ms)"

# The lock's quickshell runs with the shell's process settings, not with the
# user manager's environment the unit starts from: no KDE platform theme
# (the manager has QT_QPA_PLATFORMTHEME=kde), two allocator arenas, no Mesa
# threads, no decoration contexts.
lock STUB_STATES=inactive QT_QPA_PLATFORMTHEME=kde
run_line=$(grep '^systemd-run' "$calls" || true)
check '[[ $run_line == *" env -u QT_QPA_PLATFORMTHEME "* ]]' "the lock runs without the platform theme ($run_line)"
check '[[ $run_line != *"--setenv=QT_QPA_PLATFORMTHEME"* ]]' "and the caller's theme is not handed on"
for setting in MALLOC_ARENA_MAX=2 MALLOC_CONF=narenas:2,background_thread:true,dirty_decay_ms:1000 \
    mesa_glthread=false GALLIUM_THREAD=0 QT_WAYLAND_DISABLE_WINDOWDECORATION=1; do
  check '[[ $run_line == *" $setting "* ]]' "the lock is given $setting"
done
check '[[ $run_line == *"/quickshell --no-duplicate -p "*"/lock.qml" ]]' 'and quickshell is found as before, by the caller'
# The same values start-shell.sh gives the shell, so the two cannot drift.
for setting in MALLOC_ARENA_MAX=2 MALLOC_CONF=narenas:2,background_thread:true,dirty_decay_ms:1000 \
    mesa_glthread=false GALLIUM_THREAD=0 QT_WAYLAND_DISABLE_WINDOWDECORATION=1; do
  check 'grep -qF -- "\${${setting%%=*}:-${setting#*=}}" "$project_dir/scripts/start-shell.sh"' \
    "start-shell.sh gives the shell the same ${setting%%=*}"
done
# An exported value wins, as it does for the shell (A/B runs).
lock STUB_STATES=inactive MALLOC_CONF=narenas:4
check 'grep -q "^systemd-run .* MALLOC_CONF=narenas:4 " "$calls"' "an exported MALLOC_CONF is the lock's too"

# The test hooks (a PAM fixture, the lid override) reach the lock only from a
# nested session its files confirm. A BUCHHWIN_NESTED=1 alone can be a flag
# that leaked into a real session, and a lock on test-permit takes any
# password: they are taken out of the unit's environment then, the user
# manager's included. The preview never runs as a unit.
lock STUB_STATES=inactive BUCHHWIN_NESTED=1 BUCHHWIN_LOCK_PAM_SERVICE=test-permit BUCHHWIN_LOCK_LID_CLOSED=1 BUCHHWIN_LOCK_PREVIEW=1
run_line=$(grep '^systemd-run' "$calls" || true)
check '[[ $run_line != *"--setenv=BUCHHWIN_LOCK_PAM_SERVICE"* && $run_line != *"--setenv=BUCHHWIN_LOCK_LID_CLOSED"* ]]' \
  "a nested flag without a nested session hands on no test hook ($run_line)"
check '[[ $run_line == *" -u BUCHHWIN_LOCK_PAM_SERVICE "* && $run_line == *" -u BUCHHWIN_LOCK_LID_CLOSED "* ]]' \
  "and takes them out of the unit's environment"
check '[[ $run_line == *" -u BUCHHWIN_LOCK_PREVIEW "* && $run_line != *"--setenv=BUCHHWIN_LOCK_PREVIEW"* ]]' \
  'the preview is never a unit'
lock STUB_STATES=inactive BUCHHWIN_LOCK_PAM_SERVICE=test-permit
check '! grep -q "setenv=BUCHHWIN_LOCK_PAM_SERVICE" "$calls" && grep -q " -u BUCHHWIN_LOCK_PAM_SERVICE " "$calls"' \
  'nor does a real session that has the name'

# The host is never suspended, rebooted or powered off from a nested session -
# and a nested session is recognised by its files, not only by BUCHHWIN_NESTED.
# The testing recipe exports the nested WAYLAND_DISPLAY and signature and says
# nothing about the flag, and with the flag as the only guard `suspend` from
# there reached the real systemctl.
nested="$sandbox/nested"
mkdir -p "$nested"
printf 'wayland-9\n' > "$nested/wayland-display"
printf 'sig-9\n' > "$nested/instance"
action suspend
check 'said "^systemctl suspend"' 'outside a nested session suspend reaches systemctl (the stub)'
action suspend BUCHHWIN_NESTED=1
check '[[ $? == 0 ]] && ! said "suspend"' 'BUCHHWIN_NESTED=1 skips suspend'
action poweroff BUCHHWIN_NESTED_DIR="$nested" WAYLAND_DISPLAY=wayland-9
check '! said "poweroff"' 'the nested display (files, no flag) skips poweroff'
action reboot BUCHHWIN_NESTED_DIR="$nested" HYPRLAND_INSTANCE_SIGNATURE=sig-9
check '! said "reboot"' 'the nested signature (files, no flag) skips reboot'
action reboot BUCHHWIN_NESTED_DIR="$nested" WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE=sig-1
check 'said "^systemctl reboot"' 'a display and signature that are not the nested ones still act'
# Recognised by its files, the lock uses the nested unit and directory too.
lock STUB_STATES=inactive BUCHHWIN_NESTED_DIR="$nested" WAYLAND_DISPLAY=wayland-9 BUCHHWIN_LOCK_PAM_SERVICE=test-permit
check 'said "unit=buchhwin-shell-lock-nested"' 'the lock from a nested environment takes the nested unit name'
check 'said "setenv=BUCHHWIN_LOCK_DIR=$run/buchhwin-shell/lock-nested "' 'and the nested lock directory'
check 'said "setenv=BUCHHWIN_LOCK_PAM_SERVICE=test-permit " && ! said " -u BUCHHWIN_LOCK_PAM_SERVICE "' \
  'a nested session its files confirm hands the PAM fixture on'
# The files of a nested Hyprland that is gone are stale and name nothing: a
# real session that got the same wayland-N still suspends.
sh -c 'exit 0' & dead=$!; wait "$dead"
printf '%s\n' "$dead" > "$nested/hyprland.pid"
action poweroff BUCHHWIN_NESTED_DIR="$nested" WAYLAND_DISPLAY=wayland-9
check 'said "^systemctl poweroff"' 'stale nested files (their Hyprland gone) do not skip poweroff'
printf '%s\n' "$$" > "$nested/hyprland.pid"
action poweroff BUCHHWIN_NESTED_DIR="$nested" WAYLAND_DISPLAY=wayland-9
check '! said "poweroff"' 'with the pid alive the files still name a nested session'
rm -f "$nested/hyprland.pid"

if (( failures )); then
  printf 'session-action: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'session-action: ok\n'
