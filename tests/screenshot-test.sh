#!/usr/bin/env bash
set -euo pipefail

# scripts/screenshot.sh against stub tools in a sandbox: one selection at a
# time (Super+S pressed again while slurp was up stacked another selection
# overlay, as often as it was pressed), and the lock let go once the picture
# is taken - also while wl-copy stays behind to serve the clipboard.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-screenshottest.XXXXXX")
daemons="$sandbox/daemons"
cleanup() {
  # The stand-in wl-copy daemons, by the pids they wrote (pgrep is not on
  # every machine, and a pattern could end someone else's sleep).
  if [[ -r $daemons ]]; then
    while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$daemons"
  fi
  rm -rf -- "$sandbox"
}
trap cleanup EXIT
failures=0
check() {
  if eval "$1"; then :; else printf 'FAIL screenshot: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
mkdir -p "$bin" "$sandbox/home/Pictures" "$sandbox/runtime"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# The selection stays up for a while, the way a hand takes its time.
stub slurp 'sleep "${SLURP_SECONDS:-0}"; echo "10,10 100x100"'
stub grim 'for last; do :; done; : > "$last"'
# wl-copy forks a daemon that keeps serving the clipboard: it must not
# inherit the lock. The stand-in leaves a sleep behind with its open files.
stub wl-copy "cat >/dev/null; (exec sleep 3.141) & echo \$! >> '$daemons'; exit 0"
stub notify-send
stub xdg-user-dir "echo '$sandbox/home/Pictures'"
stub hyprctl "echo '[{\"name\":\"eDP-1\",\"focused\":true}]'"
export PATH="$bin:$PATH"
if [[ $(command -v slurp) != "$bin/slurp" ]]; then
  printf 'screenshot test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

shoot() {
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_NESTED -u BUCHHWIN_SHELL_PATH \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/runtime" BUCHHWIN_NESTED_DIR="$sandbox/no-nested" \
    "$@" bash "$project_dir/scripts/screenshot.sh" region
}
count() { grep -c "^$1 " "$calls" 2>/dev/null || true; }

# A second press while the first selection is up: no second slurp.
: > "$calls"
shoot SLURP_SECONDS=1.5 &
first=$!
sleep 0.4
shoot SLURP_SECONDS=0
check '[[ $(count slurp) -eq 1 ]]' 'a second press while selecting starts no second selection'
wait "$first"
check '[[ $(ls "$sandbox/home/Pictures/Screenshots" | wc -l) -eq 1 ]]' 'the first selection still saves its screenshot'

# The wl-copy daemon of that run is still there; the next screenshot works.
check 'kill -0 "$(head -n1 "$daemons")" 2>/dev/null' 'the stand-in clipboard daemon is still running'
: > "$calls"
shoot SLURP_SECONDS=0
check '[[ $(count slurp) -eq 1 && $(count grim) -eq 1 ]]' 'the next screenshot is not blocked by the clipboard daemon'

if (( failures )); then
  printf 'screenshot: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'TESTS PASSED screenshot\n'
