#!/usr/bin/env bash
set -euo pipefail

# Run one tests/qml/*Test.qml file in an offscreen, sandboxed Quickshell
# instance. Tests print "TESTS PASSED" or "TESTS FAILED" through console.info;
# Quickshell cannot exit itself, so the runner stops it once a marker appears.
test_file=$(readlink -f -- "$1")
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-qmltest.XXXXXX")
run_dir="$sandbox/run"
trap 'rm -rf -- "$sandbox" "$run_dir"' EXIT
output="$sandbox/output.log"

# Quickshell only loads files below the config root, so tests run from a copy
# of the repository with the test file placed at its root.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
root="$sandbox/root"
mkdir -p "$root"
tar -C "$project_dir" --exclude=.git -cf - . | tar -C "$root" -xf -
sed -e 's#"\.\./\.\./#"#g' -e 's#"\.\./fixtures/#"tests/fixtures/#g' -e 's#"Harness\.js"#"tests/qml/Harness.js"#g' \
  "$test_file" > "$root/__test__.qml"

# Without the session's compositor and shell: a test that pulls in a service
# talking to Hyprland (WallpaperTest reaches DisplayService, which runs
# `hyprctl -j monitors all`) reached the live one through the signature, and
# DisplayService's write paths are one condition away from that read
# (pitfall 82). hyprctl without a signature picks no
# instance. BUCHHWIN_SHELL_PATH is the session shell's own path.
#
# A runtime directory of its own as well: Quickshell keeps an instance
# directory (its log, lock and socket) for every start in
# $XDG_RUNTIME_DIR/quickshell, and nothing removes those before logout - in
# the user's, a tmpfs, every suite run left about a hundred, some 5 MB of
# memory. This one goes with the sandbox, and it keeps a test off the
# session's PipeWire socket too. The IPC socket in it must stay within the 108
# bytes a socket path may have (by-id/<id>/ipc.sock adds about 40): under a
# long TMPDIR it is a directory of its own in /tmp.
# Nor the session's bus: a test that pulls in NotificationService queued for
# org.freedesktop.Notifications on it, and would have taken the user's
# notifications had the shell restarted meanwhile (pitfall 82); MPRIS and the
# portal find no bus and say so. The address names a socket that never exists.
if (( ${#run_dir} > 64 )); then
  run_dir=$(mktemp -d /tmp/buchhwin-qmlrun.XXXXXX)
else
  mkdir -m 700 "$run_dir"
fi
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_SHELL_PATH QT_QPA_PLATFORM=offscreen \
  XDG_CONFIG_HOME="$sandbox/config" XDG_STATE_HOME="$sandbox/state" \
  XDG_CACHE_HOME="$sandbox/cache" XDG_RUNTIME_DIR="$run_dir" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$sandbox/no-bus" \
  quickshell -p "$root/__test__.qml" >"$output" 2>&1 &
pid=$!

# A test fails on the same Qt complaints the smoke test reads out of the
# session log (scripts/smoke-session.sh): a binding loop or a recursive
# rearrange in a component under test is a defect whether or not every
# assertion passed, and the unit test is where it is cheapest to see.
# The complaints are read first and once more after PASSED has settled: most
# tests finish in Component.onCompleted, so a warning logged while the
# component loaded is in the same poll as PASSED, and one from a binding that
# re-runs right after it lands a moment later. Checking PASSED first let both
# through.
failures='TESTS FAILED|TypeError|ReferenceError|SyntaxError|is not a type|failed to load|Binding loop|recursive rearrange|Unable to assign|Cannot assign'
status=2
for _ in {1..150}; do
  if grep -qE "$failures" "$output"; then status=1; sleep 0.2; break; fi
  if grep -q 'TESTS PASSED' "$output" || ! kill -0 "$pid" 2>/dev/null; then
    sleep 0.3
    if grep -qE "$failures" "$output" || ! grep -q 'TESTS PASSED' "$output"; then status=1; else status=0; fi
    break
  fi
  sleep 0.1
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

# ERROR too: a test that does not load prints "ERROR: Failed to load
# configuration" and the "caused by @__test__.qml[line:col]" line under it,
# and without them the run said nothing but exit 1.
sed -E 's/\x1b\[[0-9;]*m//g' "$output" | grep -E 'FAIL|TESTS|Error|ERROR|caused by|WARN|Binding loop|recursive rearrange|Unable to assign|Cannot assign' || true
if [[ $status -eq 2 ]]; then
  printf 'Timed out: %s\n' "$test_file" >&2
fi
exit "$status"
