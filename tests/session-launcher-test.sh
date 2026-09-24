#!/usr/bin/env bash
set -euo pipefail

# Session launcher, /usr/local/bin wrapper, system installer (--root), autostart
# skip list and session-init.sh order, all against stub commands in a sandbox.
# systemctl, start-hyprland, hyprctl, dbus-update-activation-environment and
# setsid are stubs that only record their arguments; the test refuses to run if
# PATH would reach the real systemctl.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-sessiontest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0

check() {
  if eval "$1"; then :; else printf 'FAIL session-launcher: %s\n' "$2"; failures=$((failures + 1)); fi
}

bin="$sandbox/bin"
calls="$sandbox/calls.log"
mkdir -p "$bin"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
stub systemctl
stub hyprctl
stub dbus-update-activation-environment
stub setsid
# start-hyprland fails for configs named in $STUB_FAIL_CONFIG.
stub start-hyprland 'case "$*" in *"${STUB_FAIL_CONFIG:-none}"*) exit 3 ;; esac; exit 0'
export PATH="$bin:$PATH"
if [[ $(command -v systemctl) != "$bin/systemctl" || $(command -v start-hyprland) != "$bin/start-hyprland" ]]; then
  printf 'session-launcher test: stubs are not first in PATH, refusing to run\n' >&2
  exit 1
fi

# A fake installed project: the real scripts with stub config files.
home="$sandbox/home"
project="$home/.local/share/buchhwin-shell"
mkdir -p "$project/hypr" "$project/scripts/lib" "$project/session" "$home/.config/buchhwin-shell"
cp "$project_dir/session/buchhwin-shell-session" "$project/session/"
cp "$project_dir/scripts/session-init.sh" "$project/scripts/"
cp "$project_dir/scripts/lib/autostart-skip.sh" "$project/scripts/lib/"
printf '#!/bin/sh\nexit 0\n' > "$project/scripts/start-shell.sh"
chmod +x "$project/scripts/start-shell.sh"
touch "$project/hypr/hyprland.conf" "$project/hypr/hyprland.lua"

# The sandbox has to be the whole environment, not most of it. A stray
# XDG_STATE_HOME from whoever ran the suite sent the startup timeline somewhere
# else and failed the check that reads it back - a test that depends on its
# caller's environment is a test that can lie about the thing under test.
launch() {
  : > "$calls"
  env -u BUCHHWIN_SHELL_PATH -u BUCHHWIN_HYPR_CONFIG -u XDG_CONFIG_HOME -u BUCHHWIN_NESTED \
    HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" \
    "$@" bash "$project/session/buchhwin-shell-session" 2>"$sandbox/stderr.log"
}
configs() { sed -n 's/^start-hyprland -- --config //p' "$calls" | xargs -rn1 basename | paste -sd' '; }

# Configuration format choice.
launch; check '[[ $(configs) == hyprland.lua ]]' "Lua is the default when hyprland.lua exists"
launch BUCHHWIN_HYPR_CONFIG=conf; check '[[ $(configs) == hyprland.conf ]]' "BUCHHWIN_HYPR_CONFIG=conf"
printf 'conf\n' > "$home/.config/buchhwin-shell/hypr-config"
launch; check '[[ $(configs) == hyprland.conf ]]' "hypr-config file selects conf"
launch BUCHHWIN_HYPR_CONFIG=lua; check '[[ $(configs) == hyprland.lua ]]' "environment wins over the file"
printf 'nonsense' > "$home/.config/buchhwin-shell/hypr-config"
launch; check '[[ $(configs) == hyprland.lua ]] && grep -q "ignoring unknown" "$sandbox/stderr.log"' "unknown file value falls back to the default"
rm "$home/.config/buchhwin-shell/hypr-config"
mv "$project/hypr/hyprland.lua" "$sandbox/hyprland.lua"
launch; check '[[ $(configs) == hyprland.conf ]]' "conf without hyprland.lua"
launch BUCHHWIN_HYPR_CONFIG=lua; check '[[ $(configs) == hyprland.conf ]]' "requested Lua without the file uses conf"
mv "$sandbox/hyprland.lua" "$project/hypr/hyprland.lua"

# Safety net: a fast Lua failure retries once with conf.
status=0; launch STUB_FAIL_CONFIG=hyprland.lua || status=$?
check '[[ $(configs) == "hyprland.lua hyprland.conf" && $status -eq 0 ]]' "failing Lua start retries with conf"
status=0; launch STUB_FAIL_CONFIG=hyprland STUB=1 || status=$?
check '[[ $(configs) == "hyprland.lua hyprland.conf" && $status -eq 3 ]]' "one retry only, its status is returned"
status=0; launch STUB_FAIL_CONFIG=hyprland.lua BUCHHWIN_LUA_FALLBACK_SECONDS=0 || status=$?
check '[[ $(configs) == hyprland.lua && $status -eq 3 ]]' "no retry after the fallback window"
status=0; launch STUB_FAIL_CONFIG=hyprland.conf BUCHHWIN_HYPR_CONFIG=conf || status=$?
check '[[ $(configs) == hyprland.conf && $status -eq 3 ]]' "conf failures are not retried"

# After the session: skipped autostart units unmasked, session target stopped.
launch
check 'grep -q "^systemctl --user unmask --runtime app-geoclue\\\\x2ddemo\\\\x2dagent@autostart.service app-sealertauto@autostart.service app-org.freedesktop.problems.applet@autostart.service$" "$calls"' "autostart units unmasked at logout"
check '[[ $(tail -n1 "$calls") == "systemctl --user stop buchhwin-shell-session.target" ]]' "session target stopped last"

# Autostart skip list.
source "$project_dir/scripts/lib/autostart-skip.sh"
check '[[ $(autostart_skip_units | paste -sd" ") == "app-geoclue\\x2ddemo\\x2dagent@autostart.service app-sealertauto@autostart.service app-org.freedesktop.problems.applet@autostart.service" ]]' "generated unit names"

# session-init.sh: environment and portal before the shell, masks before autostart.
init() {
  : > "$calls"
  env -u BUCHHWIN_NESTED HOME="$home" XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" "$@" \
    bash "$project/scripts/session-init.sh" "$project" 2>"$sandbox/stderr.log"
}
line_of() { grep -nF -- "$1" "$calls" | head -n1 | cut -d: -f1; }
init
import=$(line_of "systemctl --user import-environment")
portal=$(line_of "systemctl --user restart xdg-desktop-portal.service")
shell=$(line_of "setsid -f $project/scripts/start-shell.sh $project")
mask=$(line_of "systemctl --user mask --runtime app-geoclue")
autostart=$(line_of "systemctl --user start buchhwin-shell-autostart.target")
check '[[ -n $import && -n $portal && -n $shell && $import -lt $shell && $shell -lt $portal ]]' "shell starts after the environment import and before the portal work"
check '[[ -n $mask && -n $autostart && $shell -lt $mask && $mask -lt $autostart ]]' "skipped units masked before the autostart target"
check '[[ $(grep -c "start-shell.sh" "$calls") -eq 1 ]]' "shell started once"
timeline="$home/.local/state/buchhwin-shell/startup.log"
check '[[ -s $timeline ]] && grep -q "shell started" "$timeline"' "startup timeline written"
# The cursor step has a mark of its own, ahead of the import: without it the
# gap between "started" and "imported" is jq, hyprctl and systemctl in one
# number, and the import gets blamed for all three.
check '[[ $(grep -n "cursor set" "$timeline" | cut -d: -f1) -lt $(grep -n "environment imported" "$timeline" | cut -d: -f1) ]]' "cursor step marked before the import"
printf '{ "autostart": { "system": false } }\n' > "$home/.config/buchhwin-shell/settings.json"
init
check '! grep -q "mask\|buchhwin-shell-autostart.target" "$calls"' "autostart off: no masks, no autostart target"
rm "$home/.config/buchhwin-shell/settings.json"
stub systemctl 'case "$*" in *xdg-desktop-portal.service*) exit 1 ;; esac; exit 0'
init
check 'grep -q "start-shell.sh" "$calls" && grep -q "step failed" "$sandbox/stderr.log"' "failed portal restart still starts the shell"
stub systemctl
init BUCHHWIN_NESTED=1
check '[[ $(cat "$calls") == "setsid -f $project/scripts/start-shell.sh $project" ]]' "nested: only the shell starts"

# /usr/local/bin wrapper and the system installer below a scratch root.
root="$sandbox/root"
"$project_dir/install/system-install.sh" --root "$root" >/dev/null
wrapper="$root/usr/local/bin/buchhwin-shell-session"
check '[[ -x $wrapper ]] && cmp -s "$wrapper" "$project_dir/session/buchhwin-shell-session-wrapper"' "wrapper installed executable"
check 'grep -qx "Exec=/usr/local/bin/buchhwin-shell-session" "$root/usr/share/wayland-sessions/buchhwin-shell.desktop"' "session entry runs the wrapper"
check '[[ -f $root/etc/pam.d/buchhwin-lock && -f $root/etc/pam.d/buchhwin-lock-password ]]' "PAM services installed"
printf 'keep' > "$root/etc/pam.d/buchhwin-lock"
"$project_dir/install/system-install.sh" --root "$root" >/dev/null
check '[[ $(cat "$root/etc/pam.d/buchhwin-lock") == keep ]]' "existing PAM files kept"
: > "$calls"
status=0; env -u BUCHHWIN_SHELL_PATH -u BUCHHWIN_HYPR_CONFIG -u XDG_CONFIG_HOME HOME="$home" "$wrapper" 2>/dev/null || status=$?
check '[[ $status -eq 0 && $(configs) == hyprland.lua ]]' "wrapper runs the launcher from the home directory"
status=0; env -u BUCHHWIN_SHELL_PATH HOME="$sandbox/nobody" "$wrapper" 2>"$sandbox/stderr.log" || status=$?
check '[[ $status -eq 1 ]] && grep -q "is missing" "$sandbox/stderr.log"' "wrapper explains a missing launcher"

if (( failures )); then
  printf 'TESTS FAILED session-launcher (%d failed)\n' "$failures"
  exit 1
fi
printf 'TESTS PASSED session-launcher\n'
