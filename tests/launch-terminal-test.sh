#!/usr/bin/env bash
set -euo pipefail
# scripts/launch-terminal.sh: a command in the session's terminal (Settings >
# Default apps), with each terminal's own words for holding the window, its
# title and the command; in the foreground, through launch-app.sh (the
# session's environment, a scope or --unit's service), and kitty when nothing
# is set or the terminal is missing. Stub terminals record what they get; the
# default comes from scripts/lib/default-terminal.sh - the real default-apps.py
# where bash cannot be sure - over a sandboxed XDG tree.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-terminaltest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL launch-terminal: %s\n' "$2"; failures=$((failures + 1)); fi; }

bin="$sandbox/bin"; sys="$sandbox/sys"; calls="$sandbox/calls.log"; argv="$sandbox/last.argv"
mkdir -p "$bin" "$sys"
# Only these tools, so a terminal installed on this machine is never found
# (or started) in place of a stub.
for tool in bash sh python3 readlink dirname mktemp mkdir chmod rm env sed grep cat date head tail tr wc stat mv printf; do
  ln -sf "$(type -P "$tool")" "$sys/$tool"
done
# What Alacritty's daemon start uses (scripts/launch-alacritty.sh), where the
# machine has it: without them the window is a process of its own.
for tool in setsid flock sleep; do
  if tool_path=$(type -P "$tool"); then ln -sf "$tool_path" "$sys/$tool"; fi
done
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# systemd-run records its arguments and runs what follows `--`.
stub systemd-run 'while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
stub systemctl 'exit 0'
stub systemd-escape 'for a in "$@"; do last=$a; done; printf "%s\n" "$last" | sed "s/-/\\\\x2d/g"'
# A terminal stub writes its name, then each argument on a line of its own,
# and its environment. With RUN set it runs the command it was given: what
# follows its separator (-e or --).
term() {
  local name=$1 separator=${2:-}
  {
    printf '#!/bin/sh\n'
    printf '{ printf "%%s\\n" "${0##*/}"; for a in "$@"; do printf "%%s\\n" "$a"; done; } > "%s"\n' "$argv"
    printf 'env > "%s.env"\n' "$argv"
    if [ -n "$separator" ]; then
      printf '[ -n "${RUN:-}" ] || exit 0\n'
      printf 'while [ "$#" -gt 0 ] && [ "$1" != "%s" ]; do shift; done\n' "$separator"
      printf '[ "$#" -gt 1 ] || exit 0\nshift\nexec "$@"\n'
    fi
  } > "$bin/$name"
  chmod +x "$bin/$name"
}
term alacritty -e
term kitty
term konsole -e
term foot --
term wezterm --
term ghostty -e
term gnome-terminal --
term xterm -e
term uxterm -e
term myterm -e

# The XDG tree default-apps.py reads: entries in a data dir, the choice in
# buchhwin-shell-xdg-terminals.list. Nothing of this machine's.
data="$sandbox/data"; config="$sandbox/config"; runtime="$sandbox/runtime"
mkdir -p "$data/applications" "$sandbox/sysdata" "$config" "$runtime"
chmod 700 "$runtime"
# The user manager is there when its socket is (launch-app.sh).
mkdir -p "$runtime/systemd"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$runtime/systemd/private"
entry() {
  printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nCategories=System;TerminalEmulator;\n' "${1%.desktop}" "$2" \
    > "$data/applications/$1"
}
entry Alacritty.desktop alacritty
entry org.kde.konsole.desktop konsole
entry foot.desktop foot
entry footclient.desktop footclient
entry org.wezfurlong.wezterm.desktop "wezterm start --cwd ."
entry com.mitchellh.ghostty.desktop ghostty
entry org.gnome.Terminal.desktop gnome-terminal
entry xterm.desktop xterm
entry uxterm.desktop uxterm
entry org.example.MyTerm.desktop "env GDK_BACKEND=x11 myterm --new-window %u"
entry org.example.Boxed.desktop "/usr/bin/flatpak run --branch=stable org.example.Boxed"
use() { printf '%s\n' "$1" > "$config/buchhwin-shell-xdg-terminals.list"; }

# The caller's own environment must not decide anything below - its display
# neither: with one, Alacritty's windows go to its daemon (a case of its own
# below).
unset MALLOC_ARENA_MAX mesa_glthread GALLIUM_THREAD QS_ICON_THEME BUCHHWIN_APP_ENV_UNSET BUCHHWIN_APP_QPA_THEME RUN \
  WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
export PATH="$bin:$sys" XDG_CONFIG_HOME="$config" XDG_DATA_HOME="$data" XDG_DATA_DIRS="$sandbox/sysdata" \
  XDG_RUNTIME_DIR="$runtime" HOME="$sandbox/home"
launch=("$project_dir/scripts/launch-terminal.sh")
# Runs it with a fresh log; the status is caught, so a refusal is a FAIL line.
run() { : > "$calls"; rm -f -- "$argv" "$argv.env"; status=0; "${launch[@]}" "$@" </dev/null >"$sandbox/out" 2>&1 || status=$?; }
# The recorded call equals the given words.
got() { [[ -r $argv && $(cat "$argv") == "$(printf '%s\n' "$@")" ]]; }
shown() { tr '\n' ' ' 2>/dev/null < "$argv"; }
scope_of() { grep -qE "^systemd-run --user --scope .*--unit=app-buchhwin-$1-[0-9]+\.scope -- " "$calls"; }

# ---- each terminal's words ------------------------------------------------------
use Alacritty.desktop
run --hold --title "System upgrade" -- sh -c 'echo hi'
check 'got alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true --hold --title "System upgrade" -e sh -c "echo hi"' \
  "Alacritty through launch-alacritty.sh: --hold, --title, -e ($(shown))"
check 'scope_of Alacritty' "in Alacritty's scope ($(head -1 "$calls"))"
run --unit buchhwin-upgrade --hold -- flatpak update
check 'grep -q "^systemd-run --user --quiet --collect --slice=app.slice --unit=buchhwin-upgrade --description=Alacritty (buchhwin-shell) " "$calls" && ! grep -q -- --scope "$calls"' \
  "--unit reaches launch-alacritty.sh: a service of that name, not a scope ($(head -1 "$calls"))"
check 'got alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true --hold -e flatpak update' \
  "and Alacritty still gets its options ($(shown))"
run
check 'got alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true' "no command: Alacritty with a shell ($(shown))"
# With a display, the same words become a window of Alacritty's daemon
# (scripts/launch-alacritty.sh; its own cases are in tests/launch-app-test.sh):
# a stand-in that listens on its socket, and a `msg` that reaches it. A short
# runtime directory, for the socket's 107 bytes.
if [[ -x $sys/setsid ]]; then
  drt=$(mktemp -d /tmp/buchhwin-alacritty.XXXXXX)
  trap 'if [[ -r $drt/pids ]]; then while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$drt/pids"; fi; rm -rf -- "$sandbox" "$drt"' EXIT
  mkdir -p "$drt/systemd"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$drt/systemd/private"
  {
    printf '#!/bin/sh\n'
    printf 'case $1 in\n'
    printf '  --daemon) printf "%%s\\n" "$$" >> "%s"; exec python3 -c "import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(); time.sleep(60)" "$3" ;;\n' "$drt/pids"
    printf '  msg) { printf "%%s\\n" "${0##*/}"; for a in "$@"; do printf "%%s\\n" "$a"; done; } > "%s"\n' "$argv"
    printf '       exec python3 -c "import socket,sys; socket.socket(socket.AF_UNIX).connect(sys.argv[1])" "$3" ;;\n'
    printf 'esac\nexit 1\n'
  } > "$bin/alacritty"
  chmod +x "$bin/alacritty"
  WAYLAND_DISPLAY=wayland-9 HYPRLAND_INSTANCE_SIGNATURE=c0ffee_1700000000_42 XDG_RUNTIME_DIR="$drt" \
    run --hold --title "System upgrade" -- sh -c 'echo hi'
  check '[[ $status -eq 0 ]] && got alacritty msg --socket "$drt/buchhwin-alacritty-wayland-9-1700000000_42.sock" create-window --working-directory "$PWD" -o window.opacity=0.8 -o colors.transparent_background_colors=true --hold --title "System upgrade" -e sh -c "echo hi"' \
    "with a display, Alacritty's daemon gets the window: --hold, --title, -e ($(shown))"
  term alacritty -e
fi

use kitty.desktop
entry kitty.desktop kitty
run --unit buchhwin-flatpak-update --hold --title "Flatpak update" -- flatpak update --user -y
check "got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh --hold --title 'Flatpak update' flatpak update --user -y" \
  "kitty through launch-kitty.sh: its config, --hold, --title, the command ($(shown))"
check 'grep -q -- "--unit=buchhwin-flatpak-update " "$calls"' "as the unit"

use org.kde.konsole.desktop
run --hold --title Monitor -- htop -d 10
check 'got konsole --nofork --hold -p tabtitle=Monitor -e htop -d 10' "Konsole: --nofork, --hold, the tab title, -e ($(shown))"
check 'scope_of org.kde.konsole' "in a scope named after Konsole's entry ($(head -1 "$calls"))"
run --hold
check 'got konsole --nofork' "no command: a shell, and --hold means nothing ($(shown))"

use foot.desktop
run --hold --title Monitor -- htop
check 'got foot --hold --title=Monitor -- htop' "foot: --hold, --title=, the command after -- ($(shown))"
use footclient.desktop
run -- htop
check 'got foot -- htop' "footclient's entry runs foot itself, a process that lasts as long as the window ($(shown))"
check 'scope_of footclient' "named after the entry that was chosen"

use org.wezfurlong.wezterm.desktop
run -- htop
check 'got wezterm start --always-new-process -- htop' "WezTerm: start --always-new-process -- ($(shown))"
run --hold --title Ignored -- htop
check '[[ $(sed -n "1,6p" "$argv" | tr "\n" " ") == "wezterm start --always-new-process -- sh -c " && $(tail -n 2 "$argv" | tr "\n" " ") == "sh htop " ]]' \
  "WezTerm has no hold of its own: the wrapper, and no title ($(shown))"

use org.gnome.Terminal.desktop
run --title Monitor -- htop
check 'got gnome-terminal --wait --title=Monitor -- htop' "GNOME Terminal: --wait, --title=, -- ($(shown))"
run --hold -- htop
check '[[ $(sed -n "1,5p" "$argv" | tr "\n" " ") == "gnome-terminal --wait -- sh -c " && $(tail -n 2 "$argv" | tr "\n" " ") == "sh htop " ]]' \
  "GNOME Terminal holds through the wrapper ($(shown))"
run
check 'got gnome-terminal --wait' "no command: GNOME Terminal still waits ($(shown))"

use xterm.desktop
run --hold --title Monitor -- htop
check 'got xterm -hold -T Monitor -e htop' "xterm: -hold, -T, -e ($(shown))"
use uxterm.desktop
run --hold -- htop
check 'got uxterm -hold -e htop' "uxterm keeps its own program and xterm's words ($(shown))"

use com.mitchellh.ghostty.desktop
run --title Monitor -- printf '%s\n' "it's" '$HOME' 'a b'
script=$(sed -n 4p "$argv")
check '[[ $(sed -n "1,3p" "$argv" | tr "\n" " ") == "ghostty --title=Monitor -e " && $(wc -l < "$argv") -eq 4 ]]' \
  "Ghostty: --title= and a single word after -e ($(shown))"
check '[[ $script == "$runtime"/buchhwin-terminal.* && -x $script && $(stat -c %a "$script") == 700 ]]' \
  "the word is a one-shot script in the runtime directory, the user's alone ($script)"
out=$(sh "$script" 2>&1) || true
check '[[ $out == "$(printf "%s\n" "it'"'"'s" "\$HOME" "a b")" ]]' "it runs the command with its words intact ($(tr "\n" " " <<<"$out"))"
check '[[ ! -e $script ]]' "and removes itself"

# ---- terminals it does not know -------------------------------------------------
use org.example.MyTerm.desktop
run --hold --title Ignored -- htop
check '[[ $(sed -n "1,2p" "$argv" | tr "\n" " ") == "myterm -e " && $(wc -l < "$argv") -eq 3 && $(sed -n 3p "$argv") == "$runtime"/buchhwin-terminal.* ]]' \
  "another terminal: the program from its Exec= (past env and VAR=value), -e and one word ($(shown))"
check 'scope_of org.example.MyTerm' "in a scope named after its entry"
rm -f -- "$runtime"/buchhwin-terminal.*
RUN=1 run --hold -- sh -c 'echo "out $1"; exit 3' sh x
check '[[ $status -eq 3 ]] && grep -q "^out x$" "$sandbox/out" && grep -q "\[exit status 3\] Press Enter to close this window." "$sandbox/out"' \
  "held: the command, its exit status and a line asking for Enter (status $status: $(tr "\n" " " < "$sandbox/out"))"
check '! compgen -G "$runtime/buchhwin-terminal.*" >/dev/null' "the script is gone once it ran"
RUN=1 run -- sh -c 'echo plain; exit 4'
check '[[ $status -eq 4 ]] && [[ $(cat "$sandbox/out") == plain ]]' "not held: just the command ($status: $(tr "\n" " " < "$sandbox/out"))"
run
check 'got myterm' "no command: the program alone ($(shown))"

# The wrapper itself, where a terminal runs it after `--`.
use org.gnome.Terminal.desktop
RUN=1 run --hold -- sh -c 'echo "gnome $1"; exit 0' sh y
check '[[ $status -eq 0 ]] && grep -q "^gnome y$" "$sandbox/out" && grep -q "\[exit status 0\] Press Enter" "$sandbox/out"' \
  "the hold wrapper runs the command's words as they are (status $status: $(tr "\n" " " < "$sandbox/out"))"

# ---- kitty when there is nothing else -------------------------------------------
rm -f -- "$data/applications/kitty.desktop" "$config/buchhwin-shell-xdg-terminals.list"
run --hold -- htop
check "got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh --hold htop" "nothing chosen: kitty ($(shown))"
use org.example.Boxed.desktop
run -- htop
check "got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh htop" "a Flatpak's terminal: kitty ($(shown))"
use org.kde.konsole.desktop
rm -f -- "$bin/konsole"
run -- htop
check "got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh htop" "the chosen terminal not installed: kitty ($(shown))"
term konsole -e
# The terminal is found in bash; Python only answers what bash cannot be sure
# of, an id with a dash that may be a directory (org/example/dashed.desktop).
mv "$sys/python3" "$sandbox/python3.kept"
printf '#!/bin/sh\nprintf "python3 %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$calls" "$sandbox/python3.kept" > "$sys/python3"
chmod +x "$sys/python3"
run -- htop
check 'got konsole --nofork -e htop && ! grep -q "^python3" "$calls"' "the terminal is found without Python ($(shown); $(grep "^python3" "$calls"))"
mkdir -p "$data/applications/org/example"
entry org/example/dashed.desktop dashed
use org-example-dashed.desktop
run -- htop
check 'grep -q "^python3 .*default-apps.py get terminal" "$calls"' "a dashed id is asked of default-apps.py ($(grep "^python3" "$calls"))"
rm -f -- "$sys/python3"
run -- htop
check "got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh htop" "no python3 to ask: kitty ($(shown))"
mv "$sandbox/python3.kept" "$sys/python3"
rm -rf -- "$data/applications/org"
# launch-default.sh's terminal without a default: the same answer.
rm -f -- "$config/buchhwin-shell-xdg-terminals.list"
: > "$calls"; rm -f -- "$argv"
status=0; "$project_dir/scripts/launch-default.sh" terminal </dev/null >/dev/null 2>&1 || status=$?
check "[[ \$status -eq 0 ]] && got kitty --config '$project_dir/kitty/kitty.conf' -o shell=zsh" \
  "launch-default.sh without a default terminal goes through launch-terminal.sh ($(shown))"

# ---- the application's environment ----------------------------------------------
# launch-app.sh's restore reaches every terminal, not only kitty and Alacritty.
use org.kde.konsole.desktop
env -u QT_QPA_PLATFORMTHEME QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 \
  BUCHHWIN_APP_ENV_UNSET="MALLOC_ARENA_MAX mesa_glthread GALLIUM_THREAD QS_ICON_THEME" BUCHHWIN_APP_QPA_THEME=kde \
  "${launch[@]}" -- htop </dev/null >/dev/null 2>&1 || true
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" "$argv.env" && ! grep -qE "^(MALLOC_ARENA_MAX|mesa_glthread|GALLIUM_THREAD|QS_ICON_THEME|BUCHHWIN_APP_ENV_UNSET)=" "$argv.env"' \
  "Konsole gets the session's environment, not the shell's own settings"
run --unit buchhwin-upgrade --hold -- htop
check 'grep -q "^systemd-run --user --quiet --collect --slice=app.slice --unit=buchhwin-upgrade --description=org.kde.konsole (buchhwin-shell) " "$calls"' \
  "--unit for any terminal: launch-app.sh's service ($(head -1 "$calls"))"

# ---- refused --------------------------------------------------------------------
run --bogus -- htop
check '[[ $status -eq 2 ]] && [[ ! -e $argv ]] && grep -q "unknown option --bogus" "$sandbox/out"' "an unknown option is refused (status $status)"
run --unit
check '[[ $status -eq 2 ]] && [[ ! -e $argv ]]' "--unit without a name is refused (status $status)"
run --title "" -- htop
check '[[ $status -eq 2 ]] && [[ ! -e $argv ]]' "an empty --title is refused (status $status)"

if (( failures )); then printf 'TESTS FAILED launch-terminal (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED launch-terminal\n'
