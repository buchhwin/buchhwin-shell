#!/usr/bin/env bash
set -euo pipefail
# Applications the shell starts get the session's environment, not the
# shell's own (scripts/lib/app-env.sh, docs/testing.md pitfall 85): two
# malloc arenas, Mesa without its threads, QS_ICON_THEME and no
# QT_QPA_PLATFORMTHEME are for quickshell alone, and a Qt application started
# without the platform theme comes up in Fusion's light palette in a dark
# session (Kate, for one).
#
# 1. Where the shell starts an application: every command array in services/
#    and shell/ that names a graphical program, every shell string that runs
#    one, and every script line that runs one, goes through launch-app.sh (or
#    the session's xdg-open, which ends there). A static scan, so a new
#    `execDetached(["dolphin", …])` fails here rather than on someone's desk.
# 2. screenshot.sh's "Edit" and "Open folder", run the way the launcher runs
#    them: with the shell's environment.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-appenvtest.XXXXXX")
daemons="$sandbox/daemons"
cleanup() {
  # The stand-in wl-copy daemons, by the pids they wrote.
  if [[ -r $daemons ]]; then
    while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$daemons"
  fi
  rm -rf -- "$sandbox"
}
trap cleanup EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL app-env: %s\n' "$2"; failures=$((failures + 1)); fi; }

# ---- 1. every graphical start goes through launch-app.sh ------------------------
scan_tree() {
  python3 - "$1" <<'EOF'
import os, re, sys

root = sys.argv[1]
# Programs with a window (or a dialog). xdg-open is not in the list: by name it
# is the session's (session/bin/xdg-open, first on PATH), which ends in
# launch-app.sh.
GUI = ("kdialog kcmshell6 kcmshell5 systemsettings merkuro-calendar merkuro-contact dolphin okular kate kwrite "
       "gwenview ark kdeconnect-app kdeconnect-sms kdeconnectd swappy satty spectacle pavucontrol pavucontrol-qt "
       "nm-connection-editor blueman-manager plasma-discover alacritty konsole foot kitty firefox brave "
       "brave-browser google-chrome-stable chromium chromium-browser kde-open kde-open5 kioclient kioclient5 "
       "gtk-launch").split()
gui = "|".join(re.escape(name) for name in sorted(GUI, key=len, reverse=True))
# A command array whose first element is one of them, by name or by path.
array = re.compile(r'(?:execDetached\(|\bcommand\s*[:=]\s*)\[\s*"(?:[^"]*/)?(' + gui + r')"')
# A word in command position inside a shell string or a script line.
word = re.compile(r'(?:^|[\s;&|(`"]|\$\()(' + gui + r')(?=$|[\s;&|)`"\\])')
launcher = re.compile(r'launch-app|\$2\\"|\$\{?launch|"\$here/launch-app')
problems = []

def qml_files():
    for top in ("services", "shell"):
        for base, _, names in os.walk(os.path.join(root, top)):
            for name in names:
                if name.endswith((".qml", ".js")):
                    yield os.path.join(base, name)
    for name in ("shell.qml", "lock.qml"):
        path = os.path.join(root, name)
        if os.path.exists(path):
            yield path

for path in qml_files():
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    in_shell = False
    for number, line in enumerate(lines, 1):
        code = line.strip()
        if code.startswith("//") or code.startswith("*"):
            continue
        hit = array.search(line)
        if hit:
            problems.append(f"{os.path.relpath(path, root)}:{number}: {hit.group(1)} started without launch-app.sh")
        # A `sh -c` script, possibly continued on the next lines: joined with
        # `+` at either end of a line, or an array of lines (`[ …, … ].join`).
        if '"-c"' in line:
            in_shell = True
        if in_shell:
            script = line.split('"-c"', 1)[-1]
            for found in word.finditer(script):
                if not launcher.search(script[:found.start(1)]):
                    problems.append(f"{os.path.relpath(path, root)}:{number}: {found.group(1)} in a shell string without launch-app.sh")
            following = lines[number].strip() if number < len(lines) else ""
            if not code.endswith(("+", ",", "[", "(")) and not following.startswith("+"):
                in_shell = False

# Scripts the shell or its keys run. The launchers themselves end in
# launch-app.sh; diagnostics, installers and the suite only look a program up.
skip = {"doctor.sh", "session-check.sh", "test.sh", "smoke-session.sh", "nested-session.sh",
        "reload-shell.sh", "deploy.sh", "accounts-status.sh"}
scripts = os.path.join(root, "scripts")
for name in sorted(os.listdir(scripts)):
    path = os.path.join(scripts, name)
    if not os.path.isfile(path) or name in skip or name.startswith("launch-"):
        continue
    if not name.endswith((".sh", ".py")):
        continue
    with open(path, encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle, 1):
            code = line.strip()
            if not code or code.startswith("#"):
                continue
            command = re.compile(r'(?:^|[;&|]\s*|\)\s+|\bthen\s+|\bexec\s+|\$\()(' + gui + r')(?=\s|$|;|\))')
            for found in command.finditer(code):
                if not launcher.search(code[:found.start(1)]) and "command -v" not in code:
                    problems.append(f"scripts/{name}:{number}: {found.group(1)} run without launch-app.sh")
print("\n".join(problems))
EOF
}
scan=$(scan_tree "$project_dir")
check '[[ -z $scan ]]' "every graphical program goes through launch-app.sh:
$scan"

# The scan itself: it has to see a bare start, or it proves nothing.
probe="$sandbox/probe"
mkdir -p "$probe/services" "$probe/shell" "$probe/scripts"
cat > "$probe/services/Bare.qml" <<'EOF'
Item {
    function a() { Quickshell.execDetached(["dolphin", path]) }
    Process { command: ["/usr/bin/kdialog", "--msgbox", "x"] }
    Process { command: ["sh", "-c", "kdialog --msgbox x"] }
    Process { command: ["sh", "-c", "\"$2\" org.kde.kdialog kdialog --msgbox x", "sh", "", launchApp] }
    function b() { Quickshell.execDetached([Paths.script("launch-app.sh"), "org.kde.dolphin", "dolphin"]) }
    Process { command: ["sh", "-c", "set -e\n"
        + "kdialog --msgbox x"] }
}
EOF
printf '#!/bin/sh\ncase $a in\n  edit) swappy -f "$f" ;;\n  ok) "$here/launch-app.sh" swappy swappy -f "$f" ;;\nesac\n' > "$probe/scripts/bare.sh"
probe_scan=$(scan_tree "$probe")
check '[[ $(grep -c . <<<"$probe_scan") -eq 5 ]]' "the scan finds the five bare starts and nothing else ($(tr '\n' ' ' <<<"$probe_scan"))"
check 'grep -q "Bare.qml:2: dolphin" <<<"$probe_scan" && grep -q "Bare.qml:3: kdialog" <<<"$probe_scan" && grep -q "Bare.qml:4: kdialog in a shell string" <<<"$probe_scan" && grep -q "Bare.qml:8: kdialog in a shell string" <<<"$probe_scan" && grep -q "bare.sh:3: swappy" <<<"$probe_scan"' \
  "by name, by path, in a shell string (also one continued on the next line) and in a script"

# ---- 2. screenshot.sh's actions, started from the shell -------------------------
bin="$sandbox/bin"
calls="$sandbox/calls.log"
mkdir -p "$bin" "$sandbox/home/Pictures" "$sandbox/runtime"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
stub slurp 'echo "10,10 100x100"'
stub grim 'for last; do :; done; : > "$last"'
stub wl-copy "cat >/dev/null; (exec sleep 3.141) & echo \$! >> '$daemons'; exit 0"
stub xdg-user-dir "echo '$sandbox/home/Pictures'"
stub timeout 'shift; exec "$@"'
# The notice answers with the action the case below asks for.
stub notify-send 'cat "'"$sandbox"'/answer" 2>/dev/null || true'
# systemd-run records its arguments and runs what follows `--`; the user
# manager is there, and its environment is the session's.
stub systemd-run 'while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
stub systemctl "case \"\$*\" in *show-environment*) printf 'QT_QPA_PLATFORMTHEME=kde\n' ;; esac; exit 0"
stub systemd-escape 'for a in "$@"; do last=$a; done; printf "%s\n" "$last"'
# The user manager is there when its socket is (launch-app.sh).
mkdir -p "$sandbox/runtime/systemd"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sandbox/runtime/systemd/private"
# The editor and the session's xdg-open note the environment they got.
stub swappy "env > '$sandbox/swappy.env'"
stub xdg-open "env > '$sandbox/xdg-open.env'"
export PATH="$bin:$PATH"
if [[ $(command -v swappy) != "$bin/swappy" ]]; then
  printf 'app-env test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

# The launcher's "Screenshot: …" runs the script from quickshell, with the
# shell's own settings and start-shell.sh's record of them.
shoot() {
  env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u BUCHHWIN_NESTED -u BUCHHWIN_SHELL_PATH \
    -u QT_QPA_PLATFORMTHEME HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/runtime" \
    BUCHHWIN_NESTED_DIR="$sandbox/no-nested" QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 \
    mesa_glthread=false GALLIUM_THREAD=0 MALLOC_CONF=narenas:2 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QSG_DISTANCEFIELD_ANTIALIASING=gray BUCHHWIN_ICON_THEME_AUTO=1 \
    BUCHHWIN_APP_ENV_UNSET="MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO" \
    BUCHHWIN_APP_QPA_THEME=kde bash "$project_dir/scripts/screenshot.sh" region
}
wait_for() {
  for _ in {1..50}; do
    [[ -s $1 ]] && return 0
    sleep 0.1
  done
  return 1
}

echo edit > "$sandbox/answer"
: > "$calls"
shoot
wait_for "$sandbox/swappy.env" || true
check '[[ -s $sandbox/swappy.env ]]' "Edit opens the editor"
check 'grep -qE "^systemd-run .*--unit=app-buchhwin-swappy-[0-9]+\.scope -- swappy -f .*/Screenshots/Screenshot_.*\.png$" "$calls"' \
  "in a scope of its own, named after swappy.desktop ($(grep systemd-run "$calls" | head -1))"
check '! grep -qE "^(MALLOC_ARENA_MAX|MALLOC_CONF|mesa_glthread|GALLIUM_THREAD|QT_WAYLAND_DISABLE_WINDOWDECORATION|QSG_DISTANCEFIELD_ANTIALIASING|QS_ICON_THEME|BUCHHWIN_ICON_THEME_AUTO|BUCHHWIN_APP_[A-Z_]+)=" "$sandbox/swappy.env"' \
  "without the shell's own settings ($(grep -E "^(MALLOC|mesa|GALLIUM|QS_|BUCHHWIN_APP)" "$sandbox/swappy.env" 2>/dev/null | tr '\n' ' '))"
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" "$sandbox/swappy.env"' "and with the session's platform theme back"

echo folder > "$sandbox/answer"
: > "$calls"
shoot
wait_for "$sandbox/xdg-open.env" || true
check 'grep -qE "^xdg-open .*/home/Pictures/Screenshots$" "$calls"' \
  "Open folder hands the folder to xdg-open, the session's by PATH ($(grep xdg-open "$calls" | head -1))"

if (( failures )); then printf 'TESTS FAILED app-env (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED app-env\n'
