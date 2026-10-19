#!/usr/bin/env bash
set -euo pipefail

# scripts/screenshot.sh against stub tools in a sandbox: one selection at a
# time (Super+S pressed again while slurp was up stacked another selection
# overlay, as often as it was pressed), and the lock let go once the picture
# is taken - also while wl-copy stays behind to serve the clipboard. The
# windows on screen handed to slurp as boxes (a click picks one), --delay,
# and the text mode: what tesseract reads goes to the clipboard, and without
# its English or German data the notice names the packages instead.
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
# The notification's waiter runs under timeout: notify-send waits until its
# notice closes, and the shell's history keeps notices open for good. The
# stand-in notes whether it got the lock's descriptor, then runs the command.
stub timeout "if [ -e /proc/\$\$/fd/9 ]; then echo 'lock held by timeout' >> '$calls'; fi; shift; exec \"\$@\""
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

# The notification is sent from a background job after the script has
# returned; it gets a moment to arrive.
for _ in {1..30}; do
  [[ $(count notify-send) -ge 1 ]] && break
  sleep 0.1
done
check '[[ $(count notify-send) -ge 1 ]]' 'the screenshot is announced'
check 'grep -q "^timeout 10m notify-send --app-name=Screenshot " "$calls"' 'the notification waiter ends on its own (timeout 10m)'
check '! grep -q "^lock held" "$calls"' 'the notification waiter does not hold the screenshot lock'

# ---- a click picks a window: the windows on screen are slurp's boxes --------
# Two monitors: the laptop's shows workspace 1 with a special workspace over
# it, the other one workspace 11 with a fullscreen window. What slurp is
# handed is what a click can pick.
cat > "$sandbox/clients.json" <<'EOF'
[
 {"address":"0xa1","mapped":true,"hidden":false,"at":[0,0],"size":[960,1200],"workspace":{"id":1,"name":"1"},"fullscreen":0},
 {"address":"0xa2","mapped":true,"hidden":false,"at":[960,0],"size":[960,1200],"workspace":{"id":1,"name":"1"},"fullscreen":0},
 {"address":"0xa3","mapped":true,"hidden":true,"at":[960,0],"size":[960,1200],"workspace":{"id":1,"name":"1"},"fullscreen":0},
 {"address":"0xb1","mapped":true,"hidden":false,"at":[0,0],"size":[1920,1200],"workspace":{"id":2,"name":"2"},"fullscreen":0},
 {"address":"0xc1","mapped":true,"hidden":false,"at":[1920,0],"size":[2560,1440],"workspace":{"id":11,"name":"11"},"fullscreen":2},
 {"address":"0xc2","mapped":true,"hidden":false,"at":[1930,10],"size":[800,600],"workspace":{"id":11,"name":"11"},"fullscreen":0},
 {"address":"0xd1","mapped":true,"hidden":false,"at":[100,100],"size":[600,400],"workspace":{"id":-98,"name":"special:magic"},"fullscreen":0},
 {"address":"0xe1","mapped":true,"hidden":false,"at":[0,0],"size":[10,10],"workspace":{"id":-99,"name":"special:buchhwin-hidden"},"fullscreen":0},
 {"address":"0xf1","mapped":false,"hidden":false,"at":[5,5],"size":[50,50],"workspace":{"id":1,"name":"1"},"fullscreen":0},
 {"address":"0xf2","mapped":true,"hidden":false,"at":[-1920.6,12.2],"size":[300.7,200],"workspace":{"id":1,"name":"1"},"fullscreen":false}
]
EOF
cat > "$sandbox/monitors.json" <<'EOF'
[{"name":"eDP-1","focused":true,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":-98,"name":"special:magic"}},
 {"name":"DP-1","focused":false,"activeWorkspace":{"id":11,"name":"11"},"specialWorkspace":{"id":0,"name":""}}]
EOF
stub hyprctl "case \"\$*\" in \"-j clients\") cat '$sandbox/clients.json' ;; \"-j monitors\") cat '$sandbox/monitors.json' ;; *) echo '[]' ;; esac"
stub slurp "cat > '$sandbox/slurp.stdin'; if [ -n \"\${SLURP_CANCEL:-}\" ]; then exit 1; fi; echo '960,0 960x1200'"
: > "$calls"
shoot
printf '%s\n' '0,0 960x1200' '960,0 960x1200' '1920,0 2560x1440' '100,100 600x400' '-1921,12 300x200' > "$sandbox/boxes.expected"
check 'diff -q "$sandbox/boxes.expected" "$sandbox/slurp.stdin" >/dev/null' \
  "slurp gets the windows on screen, one box each: $(tr '\n' ';' < "$sandbox/slurp.stdin")"
check 'grep -q "^grim -g 960,0 960x1200 " "$calls"' 'the box a click picked is the picture'
# Hyprland not answering: no boxes, and not an empty line either (slurp
# refuses the whole list over one it cannot read).
stub hyprctl 'exit 1'
: > "$calls"
shoot
check '[[ ! -s $sandbox/slurp.stdin ]]' 'without Hyprland slurp gets no boxes at all'
check '[[ $(count grim) -eq 1 ]]' 'and the region works as before'
: > "$calls"
shoot SLURP_CANCEL=1
check '[[ $(count grim) -eq 0 ]]' 'a cancelled selection takes no picture'

# ---- a while later: --delay ---------------------------------------------------
: > "$calls"
started=$(date +%s%N)
shoot_args() {
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_NESTED -u BUCHHWIN_SHELL_PATH \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/runtime" BUCHHWIN_NESTED_DIR="$sandbox/no-nested" \
    "$@"
}
stub hyprctl "echo '[{\"name\":\"eDP-1\",\"focused\":true}]'"
shoot_args bash "$project_dir/scripts/screenshot.sh" --delay 1 screen
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
check '[[ $elapsed -ge 1000 ]]' "the screen is taken a second later (${elapsed} ms)"
check 'grep -q "^grim -o eDP-1 " "$calls"' 'of the focused output'
status=0; shoot_args bash "$project_dir/scripts/screenshot.sh" --delay soon screen 2>/dev/null || status=$?
check '[[ $status -eq 2 ]]' 'a delay that is no number is refused'
status=0; shoot_args bash "$project_dir/scripts/screenshot.sh" sideways 2>/dev/null || status=$?
check '[[ $status -eq 2 ]]' 'so is a mode there is none of'

# ---- text from the screen -------------------------------------------------------
# tesseract lists what it has, and reads what TESS_TEXT says is there; the
# clipboard's stand-in keeps what it was given.
stub tesseract "if [ \"\$1\" = --list-langs ]; then printf 'List of available languages in \"/usr/share/tessdata/\" (%s):\n' x; for l in \${TESS_LANGS:-}; do echo \"\$l\"; done; exit 0; fi; printf '%b' \"\${TESS_TEXT:-}\""
stub wl-copy "cat > '$sandbox/clipboard'; exit 0"
stub slurp "cat > '$sandbox/slurp.stdin'; echo '10,10 300x100'"
ocr() { shoot_args "$@" bash "$project_dir/scripts/screenshot.sh" text; }
saved_before=$(ls "$sandbox/home/Pictures/Screenshots" | wc -l)
: > "$calls"; rm -f "$sandbox/clipboard"
ocr TESS_LANGS="afr deu eng osd" TESS_TEXT='  Invoice 2026-10\nTotal: 12,50 EUR\n\n\f'
check 'grep -qE "^tesseract .*/runtime/buchhwin-ocr\.[A-Za-z0-9]+\.png stdout -l deu\+eng$" "$calls"' \
  "German and English, from a picture in the runtime directory ($(grep '^tesseract [^-]' "$calls" | head -1))"
printf '  Invoice 2026-10\nTotal: 12,50 EUR' > "$sandbox/clipboard.expected"
check 'cmp -s "$sandbox/clipboard.expected" "$sandbox/clipboard"' \
  "the text is on the clipboard, without the page's end ($(tr '\n\f' '|^' < "$sandbox/clipboard" 2>/dev/null))"
check 'grep -q "^notify-send .*Text copied Invoice 2026-10 (and 1 more line)$" "$calls"' \
  "the notice shows its first line ($(grep '^notify-send' "$calls" | head -1))"
check '! compgen -G "$sandbox/runtime/buchhwin-ocr.*" >/dev/null' 'and the picture is gone'
check '[[ $(ls "$sandbox/home/Pictures/Screenshots" | wc -l) -eq $saved_before ]]' 'no screenshot is saved for it'
: > "$calls"; rm -f "$sandbox/clipboard"
ocr TESS_LANGS="eng osd" TESS_TEXT=' \n\f'
check 'grep -q -- "-l eng$" "$calls"' 'English alone when that is all there is'
check '[[ ! -e $sandbox/clipboard ]]' 'nothing read: nothing copied'
check 'grep -q "^notify-send .*No text found" "$calls"' 'and the notice says so'
: > "$calls"
ocr TESS_LANGS="afr osd" BUCHHWIN_DISTRO=arch
check '[[ $(count slurp) -eq 0 ]]' 'without English or German data nothing is selected'
check 'grep -q "^notify-send .*Text recognition needs language data .*sudo pacman -S tesseract-data-eng tesseract-data-deu$" "$calls"' \
  "the notice names the packages ($(grep '^notify-send' "$calls" | head -1))"
: > "$calls"
ocr TESS_LANGS="afr osd" BUCHHWIN_DISTRO=fedora
check 'grep -q "sudo dnf install tesseract-langpack-eng tesseract-langpack-deu$" "$calls"' 'in the words of the distribution'

# ---- nested: no notice reaches the session's notification server ----------------
# A nested test session shares the user's session bus; its notices went to
# the live shell. They go to stderr instead, and the screenshot is kept in
# the nested state directory.
: > "$calls"
nested_err=$(shoot_args BUCHHWIN_NESTED=1 XDG_STATE_HOME="$sandbox/nested-state" bash "$project_dir/scripts/screenshot.sh" screen 2>&1 >/dev/null || true)
sleep 0.3
check '[[ $(count notify-send) -eq 0 ]]' "a nested screenshot sends no notice ($(grep '^.*notify-send' "$calls" | head -1))"
check 'grep -q "^screenshot: Screenshot saved - Screenshot_" <<<"$nested_err"' "it says so on stderr ($nested_err)"
check 'compgen -G "$sandbox/nested-state/buchhwin-shell/screenshots/Screenshot_*.png" >/dev/null' 'and keeps the picture in the nested state'
: > "$calls"
nested_err=$(shoot_args BUCHHWIN_NESTED=1 TESS_LANGS="eng osd" TESS_TEXT=' \n\f' bash "$project_dir/scripts/screenshot.sh" text 2>&1 >/dev/null || true)
check '[[ $(count notify-send) -eq 0 ]] && grep -q "No text found" <<<"$nested_err"' "nor a text one ($nested_err)"

if (( failures )); then
  printf 'screenshot: %d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'TESTS PASSED screenshot\n'
