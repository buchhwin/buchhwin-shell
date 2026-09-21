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
  *"show -p ActiveState"*) state ;;
  # The guard this test exists for used to be `is-active`, which answers yes
  # only for `active` - that is the whole bug, so the stub has to be exact.
  *is-active*) [ "$(state)" = active ] || exit 3 ;;
esac
exit 0
EOF

# Fails when $STUB_RUN_FAILS is 1 (systemd refusing a name that is still
# loaded). On success it writes the marker the real lock screen writes, so the
# caller's wait loop ends the way it would in the session.
cat > "$bin/systemd-run" <<'EOF'
#!/bin/sh
printf 'systemd-run %s\n' "$*" >> "$CALLS"
[ "${STUB_RUN_FAILS:-0}" = 1 ] && exit 1
for arg in "$@"; do
  case "$arg" in --setenv=BUCHHWIN_LOCK_DIR=*) dir=${arg#--setenv=BUCHHWIN_LOCK_DIR=} ;; esac
done
[ -n "${dir:-}" ] && echo 1 > "$dir/locked"
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
lock() {
  : > "$calls"
  : > "$count"
  rm -rf -- "$run"
  mkdir -p "$run"
  env -u BUCHHWIN_NESTED CALLS="$calls" STUB_COUNT="$count" XDG_RUNTIME_DIR="$run" "$@" \
    bash "$project_dir/scripts/session-action.sh" lock >"$sandbox/out.log" 2>&1
}
said() { grep -q "$1" "$calls"; }

# A unit that is still coming up belongs to another locker. The old guard read
# `is-active`, which is false for `activating`, and the run that followed was
# refused the name - after which the fallback stopped a lock screen that was on
# its way up. This is the regression.
lock STUB_STATES=activating
check '! said "^systemd-run"' 'a unit that is activating is left alone'
check '! said "stop"' 'a lock screen on its way up is never stopped'
check '! said "^swaylock"' 'no swaylock while another locker is coming up'

lock STUB_STATES=active
check '! said "^systemd-run"' 'a running lock screen is left alone'

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

if (( failures )); then
  printf 'session-action: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'session-action: ok\n'
