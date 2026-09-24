#!/usr/bin/env bash
set -euo pipefail

# Run one tests/qml/*Test.qml file in an offscreen, sandboxed Quickshell
# instance. Tests print "TESTS PASSED" or "TESTS FAILED" through console.info;
# Quickshell cannot exit itself, so the runner stops it once a marker appears.
test_file=$(readlink -f -- "$1")
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-qmltest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
output="$sandbox/output.log"

# Quickshell only loads files below the config root, so tests run from a copy
# of the repository with the test file placed at its root.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
root="$sandbox/root"
mkdir -p "$root"
tar -C "$project_dir" --exclude=.git -cf - . | tar -C "$root" -xf -
sed -e 's#"\.\./\.\./#"#g' -e 's#"\.\./fixtures/#"tests/fixtures/#g' -e 's#"Harness\.js"#"tests/qml/Harness.js"#g' \
  "$test_file" > "$root/__test__.qml"

env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen \
  XDG_CONFIG_HOME="$sandbox/config" XDG_STATE_HOME="$sandbox/state" \
  XDG_CACHE_HOME="$sandbox/cache" \
  quickshell -p "$root/__test__.qml" >"$output" 2>&1 &
pid=$!

# A test fails on the same Qt complaints the smoke test reads out of the
# session log (scripts/smoke-session.sh): a binding loop or a recursive
# rearrange in a component under test is a defect whether or not every
# assertion passed, and the unit test is where it is cheapest to see.
status=2
for _ in {1..150}; do
  if grep -q 'TESTS PASSED' "$output"; then status=0; break; fi
  if grep -qE 'TESTS FAILED|TypeError|ReferenceError|SyntaxError|is not a type|failed to load|Binding loop|recursive rearrange|Unable to assign|Cannot assign' "$output"; then
    status=1; sleep 0.2; break
  fi
  if ! kill -0 "$pid" 2>/dev/null; then status=1; break; fi
  sleep 0.1
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

sed -E 's/\x1b\[[0-9;]*m//g' "$output" | grep -E 'FAIL|TESTS|Error|WARN|Binding loop|recursive rearrange|Unable to assign|Cannot assign' || true
if [[ $status -eq 2 ]]; then
  printf 'Timed out: %s\n' "$test_file" >&2
fi
exit "$status"
