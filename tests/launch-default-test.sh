#!/usr/bin/env bash
set -euo pipefail
# scripts/launch-default.sh and scripts/lib/default-terminal.sh: Super+Enter
# finds the session's terminal in bash, and Super+B and Super+E the browser and
# the file manager this session's own list names, with default-apps.py's
# answer in every case; only what bash cannot answer for certain asks Python.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-defaulttest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL launch-default: %s\n' "$2"; failures=$((failures + 1)); fi; }

# A tree of its own: the real launch-default.sh, its library and
# default-apps.py; the launchers it hands over to only write down their call.
tree="$sandbox/tree"; calls="$sandbox/calls.log"
mkdir -p "$tree/scripts/lib"
cp "$project_dir/scripts/launch-default.sh" "$project_dir/scripts/default-apps.py" "$tree/scripts/"
cp "$project_dir/scripts/lib/default-terminal.sh" "$tree/scripts/lib/"
for name in launch-alacritty.sh launch-kitty.sh launch-terminal.sh launch-app.sh launch-brave.sh launch-chrome.sh \
    launch-chromium-browser.sh; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$name" "$calls" > "$tree/scripts/$name"
  chmod +x "$tree/scripts/$name"
done
# python3 notes that it was asked, then answers as itself.
bin="$sandbox/bin"; mkdir -p "$bin"
real_python=$(command -v python3)
printf '#!/bin/sh\nprintf "python3 %%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$calls" "$real_python" > "$bin/python3"
chmod +x "$bin/python3"
export PATH="$bin:$PATH"

# The XDG tree both read; nothing of this machine's.
data="$sandbox/data"; sysdata="$sandbox/sysdata"; config="$sandbox/config"
export XDG_CONFIG_HOME="$config" XDG_DATA_HOME="$data" XDG_DATA_DIRS="$sysdata" HOME="$sandbox/home" \
  XDG_CONFIG_DIRS="$sandbox/etc-xdg" XDG_CURRENT_DESKTOP=buchhwin-shell:Hyprland
reset_tree() { rm -rf "$data" "$sysdata" "$config"; mkdir -p "$data/applications" "$sysdata/applications" "$config"; }
entry() {  # entry DIR ID [extra lines]
  local dir=$1 id=$2; shift 2
  { printf '[Desktop Entry]\nName=%s\nExec=%s\nCategories=System;TerminalEmulator;\n' "${id%.desktop}" "${id%.desktop}"
    printf '%s\n' "$@"; } > "$dir/applications/$id"
}
use() { printf '%s\n' "$@" > "$config/buchhwin-shell-xdg-terminals.list"; }
bash_answer() { (source "$project_dir/scripts/lib/default-terminal.sh"; default_terminal) 2>/dev/null; }
python_answer() { "$real_python" "$project_dir/scripts/default-apps.py" get terminal 2>/dev/null; }
# same NAME: bash answers, and what it says is what default-apps.py says.
same() {
  local mine theirs status=0
  mine=$(bash_answer) || status=$?
  theirs=$(python_answer)
  check '[[ $status -eq 0 && $mine == "$theirs" ]]' "$1: bash says '$mine' (status $status), default-apps.py '$theirs'"
}

reset_tree; entry "$data" Alacritty.desktop; entry "$sysdata" kitty.desktop; use Alacritty.desktop
same "the chosen terminal"
reset_tree; entry "$sysdata" kitty.desktop
same "nothing chosen: kitty"
reset_tree
same "nothing chosen and no kitty: none"
reset_tree; entry "$sysdata" kitty.desktop; entry "$sysdata" foot.desktop; use '# a comment' '' '  ' missing.desktop foot.desktop
same "comments, blanks and a missing entry are passed over"
reset_tree; entry "$sysdata" kitty.desktop; entry "$data" foot.desktop 'Hidden=true'; entry "$sysdata" foot.desktop; use foot.desktop
same "a hidden entry hides a good copy further down"
reset_tree; entry "$sysdata" kitty.desktop; entry "$data" foot.desktop 'Type=Link'; use foot.desktop
same "a link is no application"
reset_tree; entry "$sysdata" kitty.desktop; entry "$data" foot.desktop 'Type=Application' 'Type=Link'; use foot.desktop
same "the first value of a key counts"
reset_tree; entry "$sysdata" kitty.desktop; printf '[Other]\nType=Application\n' > "$data/applications/foot.desktop"; use foot.desktop
same "no [Desktop Entry] group: not installed"
reset_tree; entry "$sysdata" kitty.desktop; entry "$data" foot.desktop '  Hidden = true  '; use foot.desktop
same "keys and values are trimmed"
reset_tree; entry "$sysdata" kitty.desktop; entry "$data" foot.desktop; printf 'foot.desktop' > "$config/buchhwin-shell-xdg-terminals.list"
same "a last line without a newline"
reset_tree; entry "$sysdata" kitty.desktop; entry "$sysdata" foot; use foot
same "an id without .desktop is not one"
reset_tree; entry "$data" Alacritty.desktop; mkdir -p "$config/buchhwin-shell-xdg-terminals.list"
same "an unreadable list: kitty or nothing"
# A dash may be a directory: org/kde/konsole.desktop is org-kde-konsole.desktop.
reset_tree; mkdir -p "$data/applications/org/kde"; entry "$data" org/kde/konsole.desktop; use org-kde-konsole.desktop
status=0; bash_answer >/dev/null || status=$?
check '[[ $status -eq 2 ]]' "a dashed id without a file of its own goes to default-apps.py (status $status)"

# The browser and the file manager this session's own list names, in bash
# too: what it answers is what default-apps.py answers, and what it cannot be
# sure of it leaves to Python (status 2).
session_list() { printf '%s\n' "$@" > "$config/buchhwin-shell-mimeapps.list"; }
session_answer() { (source "$project_dir/scripts/lib/default-terminal.sh"; default_session_app "$1") 2>/dev/null; }
# same_app CATEGORY MIME NAME
same_app() {
  local mine theirs status=0
  mine=$(session_answer "$2") || status=$?
  theirs=$("$real_python" "$project_dir/scripts/default-apps.py" get "$1" 2>/dev/null)
  check '[[ $status -eq 0 && -n $mine && $mine == "$theirs" ]]' "$3: bash says '$mine' (status $status), default-apps.py '$theirs'"
}
# defers MIME NAME
defers() {
  local status=0
  session_answer "$1" >/dev/null || status=$?
  check '[[ $status -eq 2 ]]' "$2: left to default-apps.py (status $status)"
}
reset_tree; entry "$sysdata" org.kde.dolphin.desktop; entry "$sysdata" brave-browser.desktop
session_list '[Default Applications]' 'inode/directory=org.kde.dolphin.desktop;' 'x-scheme-handler/http=brave-browser.desktop;'
same_app files inode/directory "the session's file manager"
same_app browser x-scheme-handler/http "the session's browser"
reset_tree; entry "$sysdata" org.kde.dolphin.desktop; entry "$data" foot.desktop
session_list '[Default Applications]' 'inode/directory=missing.desktop;org.kde.dolphin.desktop;'
same_app files inode/directory "a missing id is passed over"
session_list '[Default Applications]' 'inode/directory=foot.desktop;' '[Added Associations]' 'inode/directory=x.desktop;' \
  '[Default Applications]' ' inode/directory =  org.kde.dolphin.desktop;  '
same_app files inode/directory "the last entry counts, over two groups, trimmed"
reset_tree; entry "$sysdata" org.kde.dolphin.desktop; entry "$data" foot.desktop 'Hidden=true'; entry "$sysdata" foot.desktop
session_list '[Default Applications]' 'inode/directory=foot.desktop;org.kde.dolphin.desktop;'
same_app files inode/directory "a hidden entry hides a good copy further down"
reset_tree; entry "$sysdata" org.kde.dolphin.desktop
session_list '[Default Applications]' 'inode/directory=missing.desktop; org.kde.dolphin.desktop;'
defers inode/directory "an id with a space before it is no id Python finds either"
session_list '[Added Associations]' 'inode/directory=org.kde.dolphin.desktop;'
defers inode/directory "no default in the session's list"
session_list '[Default Applications]' '# inode/directory=org.kde.dolphin.desktop;'
defers inode/directory "a comment is no default"
session_list '[Default Applications]' 'inode/directory=org.kde.dolphin.desktop;' 'text/plain=caf'$'\xc3\xa9''.desktop;'
defers inode/directory "a file that is not plain ASCII"
mkdir -p "$data/applications/org/kde"; entry "$data" org/kde/thing.desktop
session_list '[Default Applications]' 'inode/directory=org-kde-thing.desktop;'
defers inode/directory "a dashed id without a file of its own"
reset_tree; entry "$sysdata" org.kde.dolphin.desktop
session_list '[Default Applications]' 'inode/directory=org.kde.dolphin.desktop;'
status=0; (export XDG_CURRENT_DESKTOP=KDE; session_answer inode/directory >/dev/null) || status=$?
check '[[ $status -eq 2 ]]' "another desktop first: its own lists come first, left to default-apps.py (status $status)"

# launch-default.sh: the terminal without Python, the rest as before.
reset_tree; entry "$data" Alacritty.desktop; use Alacritty.desktop
: > "$calls"; bash "$tree/scripts/launch-default.sh" terminal -e htop
check 'grep -qx "launch-alacritty.sh -e htop" "$calls" && ! grep -q "^python3" "$calls"' \
  "Super+Enter reaches Alacritty's launcher without Python ($(tr '\n' ' ' < "$calls"))"
reset_tree; entry "$sysdata" kitty.desktop
: > "$calls"; bash "$tree/scripts/launch-default.sh" terminal
check 'grep -qx "launch-kitty.sh " "$calls" && ! grep -q "^python3" "$calls"' "kitty when nothing is chosen ($(tr '\n' ' ' < "$calls"))"
reset_tree
: > "$calls"; bash "$tree/scripts/launch-default.sh" terminal
check 'grep -qx "launch-terminal.sh " "$calls" && ! grep -q "^python3" "$calls"' "no terminal at all: launch-terminal.sh decides ($(tr '\n' ' ' < "$calls"))"
reset_tree; mkdir -p "$data/applications/org/kde"; entry "$data" org/kde/konsole.desktop; use org-kde-konsole.desktop
: > "$calls"; bash "$tree/scripts/launch-default.sh" terminal
check 'grep -q "^python3 .*default-apps.py get terminal" "$calls" && grep -q "^launch-app.sh org-kde-konsole.desktop gtk-launch org-kde-konsole" "$calls"' \
  "a dashed id is asked of default-apps.py ($(tr '\n' ' ' < "$calls"))"
reset_tree
: > "$calls"; bash "$tree/scripts/launch-default.sh" browser
check 'grep -q "^python3 .*default-apps.py get browser" "$calls" && grep -q "^launch-brave.sh" "$calls"' \
  "a browser the session's list does not name is asked of default-apps.py ($(tr '\n' ' ' < "$calls"))"
reset_tree; entry "$sysdata" org.kde.dolphin.desktop; entry "$sysdata" brave-browser.desktop
session_list '[Default Applications]' 'inode/directory=org.kde.dolphin.desktop;' 'x-scheme-handler/http=brave-browser.desktop;'
: > "$calls"; bash "$tree/scripts/launch-default.sh" files
check 'grep -qx "launch-app.sh org.kde.dolphin dolphin" "$calls" && ! grep -qE "^python3|gtk-launch" "$calls"' \
  "Super+E: Dolphin by its program, without Python or gtk-launch ($(tr '\n' ' ' < "$calls"))"
: > "$calls"; bash "$tree/scripts/launch-default.sh" browser https://example.org/
check 'grep -qx "launch-brave.sh https://example.org/" "$calls" && ! grep -q "^python3" "$calls"' \
  "Super+B and a web search: the session's browser without Python ($(tr '\n' ' ' < "$calls"))"
# Without the library (an older tree) Python answers, as before.
rm "$tree/scripts/lib/default-terminal.sh"
reset_tree; entry "$data" Alacritty.desktop; use Alacritty.desktop
: > "$calls"; bash "$tree/scripts/launch-default.sh" terminal
check 'grep -q "^python3 .*get terminal" "$calls" && grep -qx "launch-alacritty.sh " "$calls"' "without the library default-apps.py answers"

if (( failures )); then
  printf 'TESTS FAILED launch-default (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED launch-default\n'
