#!/usr/bin/env bash
# tests/run-qml-test.sh itself, on throwaway tests that all print TESTS
# PASSED: a clean one, one with a binding loop logged while it loaded, one
# whose TypeError arrives 100 ms after PASSED, one that looks for the
# session's Hyprland signature (it must not find it), one that runs in a
# runtime directory of its own, and one that must not see the caller's
# session bus. The runner used to
# look for PASSED first, and most tests finish in Component.onCompleted, so
# the loop sat in the same poll as PASSED and the run exited 0.
set -uo pipefail
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
command -v quickshell >/dev/null 2>&1 || { printf 'qml runner test: quickshell is not installed\n'; exit 77; }
sb=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-runnertest.XXXXXX")
trap 'rm -rf -- "$sb"' EXIT
failures=0

probe() {
  local name=$1 body=$2 assertion=${3:-true}
  cat > "$sb/${name}Test.qml" <<EOF
import Quickshell
import QtQuick
import "Harness.js" as T

ShellRoot {
$body
    Component.onCompleted: {
        T.ok($assertion, "$name")
        T.finish("$name")
    }
}
EOF
}
expect() {
  local name=$1 want=$2 what=$3 rc=0
  "$project_dir/tests/run-qml-test.sh" "$sb/${name}Test.qml" >"$sb/$name.log" 2>&1 || rc=$?
  if [[ $rc -ne $want ]]; then
    printf 'FAIL qml runner: %s (exit %s, want %s)\n' "$what" "$rc" "$want"
    sed 's/^/    /' "$sb/$name.log"
    failures=$((failures + 1))
  fi
}

probe Clean ''
probe Loop '    Item { property int a: b + 1; property int b: a + 1 }'
probe Late '    Timer { interval: 100; running: true; onTriggered: { const gone = null; console.log(gone.length) } }'
# The session's Hyprland signature and shell path stay outside: a service a
# test pulls in reached the live compositor through them (pitfall 82).
probe Session '' '!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") && !Quickshell.env("BUCHHWIN_SHELL_PATH")'
# Not in the caller's runtime directory: Quickshell leaves an instance
# directory there for every start, in the user's tmpfs until logout.
mkdir -m 700 "$sb/caller-run"
probe Runtime '' 'Quickshell.env("XDG_RUNTIME_DIR").length > 0 && Quickshell.env("XDG_RUNTIME_DIR") !== "'"$sb/caller-run"'"'
# Nor the caller's session bus: a test that made NotificationService
# queued for the notification name there (pitfall 82).
probe Bus '' 'Quickshell.env("DBUS_SESSION_BUS_ADDRESS") !== "unix:path=/nonexistent/caller-bus"'

expect Clean 0 "a clean test passes"
expect Loop 1 "a binding loop next to PASSED fails the test"
expect Late 1 "a TypeError right after PASSED fails the test"
HYPRLAND_INSTANCE_SIGNATURE=runner-probe BUCHHWIN_SHELL_PATH=/nowhere \
  expect Session 0 "the session's signature and shell path do not reach a test"
XDG_RUNTIME_DIR="$sb/caller-run" expect Runtime 0 "a test runs in a runtime directory of its own"
DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/caller-bus expect Bus 0 "a test does not reach the caller's session bus"
if [[ -n $(ls -A "$sb/caller-run" 2>/dev/null) ]]; then
  printf "FAIL qml runner: a test left something in the caller's runtime directory: %s\n" "$(ls -A "$sb/caller-run")"
  failures=$((failures + 1))
fi

if (( failures )); then printf 'TESTS FAILED qml runner (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED qml runner\n'
