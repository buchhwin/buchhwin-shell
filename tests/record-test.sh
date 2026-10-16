#!/usr/bin/env bash
# scripts/record.sh's supervisor with a stand-in recorder, notify-send and
# timeout. The "Recording saved" notice waits for its answer, and the shell
# keeps notices in its history: unbounded, the supervisor and its notify-send
# stayed for the whole session after every recording - the waiter pitfall 78
# describes, which screenshot.sh, drives and updates had already bounded.
set -uo pipefail
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sb=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-recordtest.XXXXXX")
trap 'rm -rf -- "$sb"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL record: %s\n' "$2"; failures=$((failures + 1)); fi; }
command -v jq >/dev/null 2>&1 || { printf 'record test: jq is missing (record.sh needs it)\n' >&2; exit 1; }

bin="$sb/bin"; calls="$sb/calls.log"
mkdir -p "$bin" "$sb/out" "$sb/state"
# timeout records its bound and runs the rest; notify-send records and says
# nothing was clicked; what an answer would start is recorded, never run.
printf '#!/bin/sh\necho "timeout $*" >> "%s"\nshift\nexec "$@"\n' "$calls" > "$bin/timeout"
for tool in notify-send xdg-open busctl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$calls" > "$bin/$tool"
done
chmod +x "$bin"/*
export PATH="$bin:$PATH"
[[ $(command -v notify-send) == "$bin/notify-send" ]] || { printf 'record test: stubs are not first in PATH\n' >&2; exit 1; }

record() {
  : > "$calls"
  "$project_dir/scripts/record.sh" --state "$sb/state/recording.json" start --file "$sb/out/rec.mp4" \
    --mode screen --backend wf-recorder "$@" -- sh -c 'printf data > "$1"' sh "$sb/out/rec.mp4" >/dev/null 2>&1
  # The supervisor runs detached; it is done once the state file is gone
  # (and, asked to notify, once the notice went out).
  for _ in {1..50}; do
    if [[ ! -e $sb/state/recording.json ]] && { [[ $* != *--notify* ]] || grep -q notify-send "$calls"; }; then break; fi
    sleep 0.1
  done
}

record --notify
check 'grep -q "^timeout 10m notify-send --app-name=Screen recording .*--action=open=Open --action=folder=Show in folder Recording saved rec.mp4" "$calls"' \
  "the saved notice is bounded like screenshot.sh's ($(head -1 "$calls"))"
check '[[ $(grep -c "^notify-send" "$calls") == $(grep -c "^timeout 10m notify-send" "$calls") ]]' "and never sent unbounded"
check '! grep -qE "^(xdg-open|busctl)" "$calls"' "no answer, nothing opened"
check '[[ -s $sb/out/rec.mp4 ]]' "the recording is kept"

rm -f "$sb/out/rec.mp4"
record
sleep 0.5
check '! grep -q notify-send "$calls"' "without --notify (a nested session) nothing is sent"

if (( failures )); then printf 'TESTS FAILED record (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED record\n'
