#!/usr/bin/env bash
set -euo pipefail
# scripts/launch-app.sh and session/bin/xdg-open: an application starts in a
# systemd scope named after its desktop entry, which is the name the portals
# know it by (see launch-app.sh for the key that went missing without it), and
# the session's xdg-open wraps the system's one the same way.
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/buchhwin-launchtest.XXXXXX")
trap 'rm -rf -- "$sandbox"' EXIT
failures=0
check() { if eval "$1"; then :; else printf 'FAIL launch-app: %s\n' "$2"; failures=$((failures + 1)); fi; }

bin="$sandbox/bin"; sys="$sandbox/sys"; calls="$sandbox/calls.log"
mkdir -p "$bin" "$sys"
stub() {
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n%s\n' "$1" "$calls" "${2:-exit 0}" > "$bin/$1"
  chmod +x "$bin/$1"
}
# systemd-run records its arguments and runs what follows `--`.
stub systemd-run 'while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done; shift; exec "$@"'
# The user manager's environment is the session's: $sandbox/session-env.
stub systemctl "case \"\$*\" in *show-environment*) cat \"$sandbox/session-env\" 2>/dev/null ;; esac; exit 0"
: > "$sandbox/session-env"
# The shell's own settings and its record of them (scripts/lib/app-env.sh)
# come from whoever runs this test - a terminal or an editor the shell
# started has them - and would change what every launch below runs with.
unset MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION \
  QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO BUCHHWIN_APP_ENV_UNSET BUCHHWIN_APP_QPA_THEME
# The user manager is there when its socket is (launch-app.sh): one in the
# sandbox's runtime directory, so the result does not depend on whether the
# machine running this has a user manager (CI's container has none).
mkdir -p "$sandbox/run/systemd"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$sandbox/run/systemd/private"
export XDG_RUNTIME_DIR="$sandbox/run"
# launch-app.sh escapes the unit name itself now; a systemd-escape it still
# called would show up in the log.
stub systemd-escape 'exit 1'
stub xdg-settings 'echo com.brave.Browser.desktop'
# The browsers, the notification a refused start sends, and the bus: the
# wallet is open unless a case below says otherwise.
stub brave-browser
stub google-chrome-stable
stub chromium-browser
stub notify-send
# ksecretd holds its own name; the bus driver says so (NameHasOwner), as
# scripts/wallet-unlock.sh asks it.
owned='case "$*" in *" NameHasOwner s org.kde.ksecretd") echo "b true" ;; *" NameHasOwner s "*) echo "b false" ;; *) printf "NAME PID PROCESS\norg.kde.ksecretd 42 ksecretd\n" ;; esac'
wallet_open() { stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"; }
wallet_open
stub xdg-mime 'case "$*" in "query default x-scheme-handler/mailto") echo org.kde.kmail2.desktop ;; "query filetype "*) echo text/plain ;; "query default text/plain") echo org.kde.kate.desktop ;; *) echo "" ;; esac'
# The "system" xdg-open, further down PATH than the session's.
printf '#!/bin/sh\nprintf "real-xdg-open %%s\\n" "$*" >> "%s"\n' "$calls" > "$sys/xdg-open"; chmod +x "$sys/xdg-open"
export PATH="$project_dir/session/bin:$bin:$sys:$PATH"

# ---- launch-app.sh ------------------------------------------------------------
: > "$calls"
out=$("$project_dir/scripts/launch-app.sh" brave-browser printf 'ran %s' hello)
check '[[ $out == "ran hello" ]]' "the command runs inside the scope (got: $out)"
check 'grep -qE "^systemd-run --user --scope --quiet --collect --slice=app.slice --unit=app-buchhwin-brave\\\\x2dbrowser-[0-9]+\.scope -- printf ran %s hello$" "$calls"' \
  "a scope named app-buchhwin-<escaped id>-<pid>, in app.slice, collected even when it failed ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
"$project_dir/scripts/launch-app.sh" com.brave.Browser.desktop true
check 'grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- true$" "$calls"' "the .desktop suffix is dropped from the id"
status=0; "$project_dir/scripts/launch-app.sh" only-an-id >/dev/null 2>&1 || status=$?
check '[[ $status -eq 2 ]]' "an id without a command is refused"
check '! grep -q "^systemd-escape" "$calls"' "the unit name is escaped without systemd-escape"
# Its escaping is systemd-escape's, byte for byte, where the real one exists.
if [[ -x /usr/bin/systemd-escape ]]; then
  source <(sed -n '/^unit_escape() {/,/^}/p' "$project_dir/scripts/launch-app.sh")
  for name in Alacritty brave-browser org.kde.okular .hidden 'a b' 'Ü-x' crx_abc a/b x:y_z.1 'a.b-c~d' "tab$(printf '\t')x" '-lead' 'trail.'; do
    unit_escape "$name"
    expected=$(/usr/bin/systemd-escape -- "$name")
    check '[[ $escaped == "$expected" ]]' "escaping $name: $escaped, systemd-escape says $expected"
  done
fi
# Citrix's subscribed apps have ids with spaces and a '$' (desktop entries the
# Workspace app writes): the scope is named after them all the same.
: > "$calls"
status=0; "$project_dir/scripts/launch-app.sh" 'Citrix_subscribed_XenApp 7.x.RDS-Desk $S101-255.desktop' true || status=$?
check '[[ $status -eq 0 ]] && grep -qF -- "--unit=app-buchhwin-Citrix_subscribed_XenApp\x207.x.RDS\x2dDesk\x20\x24S101\x2d255-" "$calls"' \
  "an id with spaces and a dollar names its scope ($(grep systemd-run "$calls" | head -1))"
# A unit name has at most 255 characters: an id that escapes past that is cut
# at the edge of an escape, and the application still starts.
long_id="Citrix_subscribed_$(printf '%0.s- $' {1..30})end"
: > "$calls"
status=0; out=$("$project_dir/scripts/launch-app.sh" "$long_id" printf started) || status=$?
unit_name=$(grep -oE -- '--unit=[^ ]+' "$calls" | head -1); unit_name=${unit_name#--unit=}
check '[[ $status -eq 0 && $out == started && ${#unit_name} -le 255 && $unit_name =~ ^app-buchhwin-Citrix_subscribed_(\\x2d\\x20\\x24)*(\\x2d|\\x2d\\x20)?-[0-9]+\.scope$ ]]' \
  "a long id is cut at an escape's edge, within 255 characters (${#unit_name}: $unit_name)"
# A user manager without its socket - a container, a login without one: the
# command runs as it is, with systemd-run on PATH.
: > "$calls"
out=$(XDG_RUNTIME_DIR="$sandbox/no-manager" "$project_dir/scripts/launch-app.sh" kitty printf alone)
check '[[ $out == alone ]] && ! grep -q "^systemd-run" "$calls"' "no manager socket: the command runs without a unit"
# No systemd-run anywhere: the command runs as it is.
mkdir -p "$sandbox/min"; ln -s /usr/bin/printf "$sandbox/min/printf" 2>/dev/null || true
: > "$calls"
out=$(PATH="$sandbox/min" /bin/bash "$project_dir/scripts/launch-app.sh" kitty printf plain)
check '[[ $out == plain && ! -s $calls ]]' "without systemd-run the command simply runs"
# Citrix Workspace: daemons an earlier start left behind are looked for
# first (scripts/citrix-locks.py --before-start, here a python3 that only
# records it - this test never looks at the machine's Citrix), before the
# scope; for nothing else, and not from a nested session.
mkdir -p "$sandbox/py"
printf '#!/bin/sh\nprintf "python3 %%s\\n" "$*" >> "%s"\n' "$calls" > "$sandbox/py/python3"; chmod +x "$sandbox/py/python3"
: > "$calls"
out=$(PATH="$sandbox/py:$PATH" BUCHHWIN_NESTED='' "$project_dir/scripts/launch-app.sh" citrix-workspace.desktop printf ws)
check '[[ $out == ws ]] && [[ $(head -1 "$calls") == "python3 $project_dir/scripts/citrix-locks.py --before-start" ]] && grep -q "^systemd-run .*citrix\\\\x2dworkspace-" "$calls"' \
  "Workspace's leftovers are seen to before its scope starts ($(tr '\n' ' ' < "$calls"))"
: > "$calls"
out=$(PATH="$sandbox/py:$PATH" BUCHHWIN_NESTED=1 "$project_dir/scripts/launch-app.sh" citrix-workspace printf ws)
check '[[ $out == ws ]] && ! grep -q "^python3" "$calls"' "a nested session leaves the real session's Citrix alone"
: > "$calls"
out=$(PATH="$sandbox/py:$PATH" BUCHHWIN_NESTED='' "$project_dir/scripts/launch-app.sh" 'Citrix_subscribed_Desk' printf desk)
check '[[ $out == desk ]] && ! grep -q "^python3" "$calls"' "any other start runs no helper"
printf '#!/bin/sh\nexit 1\n' > "$sandbox/py/python3"
out=$(PATH="$sandbox/py:$PATH" BUCHHWIN_NESTED='' "$project_dir/scripts/launch-app.sh" citrix-workspace printf ws)
check '[[ $out == ws ]]' "a helper that fails stops no start"

# ---- the application's environment ---------------------------------------------
# What start-shell.sh sets for the shell alone is undone before the
# application runs: the settings it recorded as its own go, the platform theme
# the shell runs without comes back, and the record itself goes too. A value
# the session had (not in the record) stays, and nothing outside the shell's
# own names is ever unset.
appenv() { tr '\0' '\n' < /proc/self/environ; }
shell_env=(QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 MALLOC_CONF=narenas:2 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QSG_DISTANCEFIELD_ANTIALIASING=gray BUCHHWIN_ICON_THEME_AUTO=1
           BUCHHWIN_APP_ENV_UNSET="MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO PATH"
           BUCHHWIN_APP_QPA_THEME=kde)
out=$(env -u QT_QPA_PLATFORMTHEME "${shell_env[@]}" "$project_dir/scripts/launch-app.sh" org.kde.dolphin env)
check '! grep -qE "^(MALLOC_ARENA_MAX|MALLOC_CONF|mesa_glthread|GALLIUM_THREAD|QT_WAYLAND_DISABLE_WINDOWDECORATION|QSG_DISTANCEFIELD_ANTIALIASING|QS_ICON_THEME|BUCHHWIN_ICON_THEME_AUTO)=" <<<"$out"' \
  "the shell's own settings do not reach the application ($(grep -E "^(MALLOC|mesa|GALLIUM|QS_)" <<<"$out" | tr '\n' ' '))"
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" <<<"$out"' "the session's platform theme is back"
check '! grep -q "^BUCHHWIN_APP_" <<<"$out"' "and the record goes with them"
check 'grep -q "^PATH=" <<<"$out"' "a name outside the shell's own is never unset"
out=$(env -u QT_QPA_PLATFORMTHEME MALLOC_ARENA_MAX=4 BUCHHWIN_APP_ENV_UNSET="mesa_glthread" BUCHHWIN_APP_QPA_THEME= mesa_glthread=false \
  "$project_dir/scripts/launch-app.sh" org.kde.dolphin env)
check 'grep -qx "MALLOC_ARENA_MAX=4" <<<"$out" && ! grep -q "^mesa_glthread=" <<<"$out"' "a value the session exported stays"
check '! grep -q "^QT_QPA_PLATFORMTHEME=" <<<"$out"' "no platform theme where the session had none"
# A caller from a shell older than the record (an editor opened from the
# launcher before it) has the settings without it: the user manager's
# environment is the session's, so what it lacks goes and its theme comes back.
printf 'QT_QPA_PLATFORMTHEME=kde\nGALLIUM_THREAD=0\n' > "$sandbox/session-env"
out=$(env -u QT_QPA_PLATFORMTHEME QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 \
  "$project_dir/scripts/launch-app.sh" org.kde.dolphin env)
check '! grep -qE "^(MALLOC_ARENA_MAX|mesa_glthread|QS_ICON_THEME)=" <<<"$out" && grep -qx "GALLIUM_THREAD=0" <<<"$out"' \
  "an old shell's settings go unless the session has them ($(grep -E "^(MALLOC|mesa|GALLIUM|QS_)" <<<"$out" | tr '\n' ' '))"
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" <<<"$out"' "and the session's platform theme comes back from the user manager"
: > "$sandbox/session-env"
# And end to end, as /proc sees it: the environ of the process launch-app.sh
# runs, with the record start-shell.sh writes.
env -u QT_QPA_PLATFORMTHEME "${shell_env[@]}" "$project_dir/scripts/launch-app.sh" org.kde.dolphin \
  sh -c 'tr "\0" "\n" < /proc/$$/environ > "$1"' sh "$sandbox/environ"
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" "$sandbox/environ" && ! grep -qE "^(MALLOC_ARENA_MAX|mesa_glthread|GALLIUM_THREAD)=" "$sandbox/environ"' \
  "the launched process's own environ is the session's"

# ---- launch-app.sh --unit ------------------------------------------------------
# The terminals of Settings > Updates: a transient service of the given name,
# not a scope - a scope keeps the application in the caller's process tree,
# and a shell that stops cleanly ended the pacman in it. The service gets the
# caller's display, XDG dirs and zsh profile on top of the manager's
# environment, and never the shell's own settings.
: > "$calls"
env -u QT_QPA_PLATFORMTHEME "${shell_env[@]}" WAYLAND_DISPLAY=wayland-7 ZDOTDIR=/z XDG_CONFIG_HOME=/c \
  LANG=en_US.UTF-8 LC_TIME=de_DE.UTF-8 \
  "$project_dir/scripts/launch-app.sh" --unit buchhwin-upgrade kitty printf 'ran %s' unit > "$sandbox/out.txt"
run_line=$(grep "^systemd-run" "$calls" | head -1)
check '[[ $(cat "$sandbox/out.txt") == "ran unit" ]]' "the command runs as the service"
check '[[ $run_line == "systemd-run --user --quiet --collect --slice=app.slice --unit=buchhwin-upgrade --description=kitty (buchhwin-shell) "* ]] && [[ $run_line != *--scope* ]]' \
  "a transient service of that name, not a scope ($run_line)"
check '[[ $run_line == *"--setenv=WAYLAND_DISPLAY=wayland-7 "* && $run_line == *"--setenv=ZDOTDIR=/z "* && $run_line == *"--setenv=XDG_CONFIG_HOME=/c "* ]]' \
  "with the caller's display, zsh profile and XDG dirs"
check '[[ $run_line == *"--setenv=LANG=en_US.UTF-8 "* && $run_line == *"--setenv=LC_TIME=de_DE.UTF-8 "* ]]' \
  "and the caller's locale"
check '[[ $run_line == *"--setenv=QT_QPA_PLATFORMTHEME=kde "* && $run_line != *MALLOC_ARENA_MAX* && $run_line != *QS_ICON_THEME* ]]' \
  "the session's platform theme, none of the shell's settings"
check '[[ $run_line == *" -- printf ran %s unit" ]]' "and the command after --"
# A nested session's unit is still the sandbox's: nested-session.sh stop
# finds its processes by BUCHHWIN_NESTED, the sandbox's XDG_CONFIG_HOME and
# the compositor's BUCHHWIN_NESTED_MODE.
: > "$calls"
env -u QT_QPA_PLATFORMTHEME "${shell_env[@]}" BUCHHWIN_NESTED=1 BUCHHWIN_NESTED_MODE=1920x1200 XDG_CONFIG_HOME=/n/config \
  "$project_dir/scripts/launch-app.sh" --unit buchhwin-upgrade kitty true
run_line=$(grep "^systemd-run" "$calls" | head -1)
check '[[ $run_line == *"--setenv=BUCHHWIN_NESTED=1 "* && $run_line == *"--setenv=BUCHHWIN_NESTED_MODE=1920x1200 "* && $run_line == *"--setenv=XDG_CONFIG_HOME=/n/config "* ]]' \
  "a nested session's unit keeps the marks its stop finds it by ($run_line)"
# launch-kitty.sh hands --unit on, with its own configuration intact.
stub kitty
: > "$calls"
XDG_CONFIG_HOME="$sandbox/kitty-cfg" "$project_dir/scripts/launch-kitty.sh" --unit buchhwin-flatpak-update --hold flatpak update
run_line=$(grep "^systemd-run" "$calls" | head -1)
check '[[ $run_line == *"--unit=buchhwin-flatpak-update "* && $run_line == *" -- kitty --config $project_dir/kitty/kitty.conf "*"-o shell=zsh --hold flatpak update" ]]' \
  "launch-kitty.sh --unit runs kitty as that unit ($run_line)"
check '[[ $run_line == *"--setenv=ZDOTDIR=$project_dir/zsh "* ]]' "with the session's zsh profile"
: > "$calls"
XDG_CONFIG_HOME="$sandbox/kitty-cfg" "$project_dir/scripts/launch-kitty.sh" --hold true
check 'grep -qE "^systemd-run --user --scope .*--unit=app-buchhwin-kitty-[0-9]+\.scope -- kitty " "$calls"' "without --unit kitty keeps its scope"
check '! grep -q "colors-light.conf" "$calls"' "no settings: kitty is dark"
# The light theme and the account's own zsh, both read by one jq.
mkdir -p "$sandbox/kitty-light/buchhwin-shell"
printf '{ "appearance": { "theme": "light" }, "terminal": { "personalShell": true } }\n' \
  > "$sandbox/kitty-light/buchhwin-shell/settings.json"
stub kitty 'printf "ZDOTDIR=%s\n" "${ZDOTDIR:-}" >> "'"$calls"'"'
: > "$calls"
ZDOTDIR=/elsewhere XDG_CONFIG_HOME="$sandbox/kitty-light" "$project_dir/scripts/launch-kitty.sh"
check 'grep -q -- "--config $project_dir/terminal/colors-light.conf" "$calls" && grep -qx "ZDOTDIR=" "$calls"' \
  "light theme and the personal shell: the light colours, no session zsh ($(tr '\n' ' ' < "$calls"))"
printf '{ "appearance": { "theme": "dark" } }\n' > "$sandbox/kitty-light/buchhwin-shell/settings.json"
: > "$calls"
XDG_CONFIG_HOME="$sandbox/kitty-light" "$project_dir/scripts/launch-kitty.sh"
check '! grep -q "colors-light.conf" "$calls" && grep -qx "ZDOTDIR=$project_dir/zsh" "$calls"' \
  "dark and no personal shell: the session's zsh ($(tr '\n' ' ' < "$calls"))"
stub kitty
# No user manager: still out of the caller's tree (setsid), and nothing waits.
mkdir -p "$sandbox/min2"
for tool in sh setsid; do ln -sf "$(command -v "$tool")" "$sandbox/min2/$tool"; done
rm -f "$sandbox/unit-ran"
status=0; PATH="$sandbox/min2" /bin/bash "$project_dir/scripts/launch-app.sh" --unit buchhwin-upgrade kitty \
  sh -c 'echo ran > "$1"' sh "$sandbox/unit-ran" || status=$?
for _ in {1..20}; do [[ -s $sandbox/unit-ran ]] && break; sleep 0.05; done
check '[[ $status -eq 0 && -s $sandbox/unit-ran ]]' "without a user manager --unit still runs the command (status $status)"

# ---- scripts/launch-brave.sh ----------------------------------------------------
# Plasma's password store, in its own scope, only with the wallet open. Every
# start's status is caught: under set -e a refused start would otherwise end
# the whole test here, without a FAIL line to say which.
: > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" --new-window || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave-browser --password-store=kwallet6 --new-window$" "$calls"' \
  "Brave starts with --password-store=kwallet6, the key Plasma's Brave uses ($(grep systemd-run "$calls" | head -1))"
check 'grep -q "^brave-browser --password-store=kwallet6 --new-window$" "$calls"' "and the arguments reach Brave"
check 'grep -q -- "--auto-start=no .*get-property org.kde.ksecretd" "$calls" && ! grep -q Unlock "$calls"' \
  "the wallet is read first, and an open one is not asked anything"
# Shut, and the service offers no prompt: no Brave, and a notification why.
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *Unlock*) printf 'ao 0 o \"/\"\n' ;; *) $owned ;; esac"
: > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^brave-browser" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Brave (status $status)"
check 'grep -q "^notify-send .*Brave not started" "$calls"' "and the user is told why"
# Shut, prompt offered and answered: Brave starts after the prompt.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"/org/freedesktop/secrets/prompt/p1\"\n' ;; *\"Secret.Prompt Prompt\"*) touch \"$sandbox/prompted\" ;; *get-property*) if [ -e \"$sandbox/prompted\" ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
rm -f "$sandbox/prompted"; : > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" || status=$?
check '[[ $status -eq 0 ]] && grep -q "Secret.Prompt Prompt" "$calls" && grep -q "^brave-browser --password-store=kwallet6$" "$calls"' "the prompt is followed and Brave starts once the wallet is open (status $status)"
# Shut, prompt dismissed: no Brave.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"/org/freedesktop/secrets/prompt/p1\"\n' ;; *\"Secret.Prompt Prompt\"*) touch \"$sandbox/prompted\" ;; *introspect*) if [ -e \"$sandbox/prompted\" ]; then exit 1; fi ;; *get-property*) echo 'b true' ;; *) $owned ;; esac"
rm -f "$sandbox/prompted"; : > "$calls"
status=0; "$project_dir/scripts/launch-brave.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^brave-browser" "$calls" && grep -q "^notify-send" "$calls"' "a dismissed prompt means no Brave (status $status)"
wallet_open
# Arch: the AUR's brave-bin is /usr/bin/brave, and gnome-keyring holds the
# generic secret service name while ksecretd answers on its own. Only where
# this machine has no real brave-browser, which would otherwise be started.
rm -f "$bin/brave-browser"
stub brave
if ! command -v brave-browser >/dev/null 2>&1; then
  stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"
  : > "$calls"
  status=0; "$project_dir/scripts/launch-brave.sh" --new-window || status=$?
  check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave --password-store=kwallet6 --new-window$" "$calls"' \
    "Arch: Brave starts as brave, same id and password store ($(grep systemd-run "$calls" | head -1))"
  check 'grep -q -- "get-property org.kde.ksecretd" "$calls"' "Arch: the wallet is read from ksecretd, not gnome-keyring"
fi
rm -f "$bin/brave"
stub brave-browser
wallet_open

# ---- scripts/launch-chrome.sh, launch-chromium-browser.sh ----------------------
# Chrome and Chromium keep the same two keys in the wallet as Brave, so they
# share its guard (scripts/launch-chromium.sh): the password store, a scope
# named after their entries, and no start against a shut wallet.
: > "$calls"
status=0; "$project_dir/scripts/launch-chrome.sh" --new-window || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-com\.google\.Chrome-[0-9]+\.scope -- google-chrome-stable --password-store=kwallet6 --new-window$" "$calls"' \
  "Chrome starts with --password-store=kwallet6 in a scope of its own ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium-browser.sh" || status=$?
check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-chromium\\\\x2dbrowser-[0-9]+\.scope -- chromium-browser --password-store=kwallet6$" "$calls"' \
  "Chromium starts with --password-store=kwallet6 in a scope of its own ($(grep systemd-run "$calls" | head -1))"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium.sh" com.google.Chrome >/dev/null 2>&1 || status=$?
check '[[ $status -ne 0 ]] && ! grep -q systemd-run "$calls"' "launch-chromium.sh without a command is refused (status $status)"
# Shut, no prompt offered: neither starts, and the notification names the browser.
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *Unlock*) printf 'ao 0 o \"/\"\n' ;; *) $owned ;; esac"
: > "$calls"
status=0; "$project_dir/scripts/launch-chrome.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^google-chrome-stable" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Chrome (status $status)"
check 'grep -q "^notify-send .*Google Chrome not started" "$calls"' "and the notification names Chrome"
: > "$calls"
status=0; "$project_dir/scripts/launch-chromium-browser.sh" >/dev/null 2>&1 || status=$?
check '[[ $status -eq 1 ]] && ! grep -q "^chromium-browser" "$calls" && ! grep -q systemd-run "$calls"' "a shut wallet means no Chromium (status $status)"
check 'grep -q "^notify-send .*Chromium not started" "$calls"' "and the notification names Chromium"
wallet_open

# ---- session/bin/xdg-open -------------------------------------------------------
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- brave-browser --password-store=kwallet6 https://example.org/page$" "$calls"' \
  "a web link for Brave goes through launch-brave.sh: Plasma's store, the browser's scope"
check 'grep -q "^brave-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "and Brave gets the link, not the system xdg-open"
# Chrome or Chromium as the default browser: the link takes their launchers.
stub xdg-settings 'echo google-chrome.desktop'
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-com\.google\.Chrome-[0-9]+\.scope -- google-chrome-stable --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for Chrome goes through launch-chrome.sh"
stub xdg-settings 'echo chromium-browser.desktop'
: > "$calls"
xdg-open https://example.org/page
check 'grep -qE "unit=app-buchhwin-chromium\\\\x2dbrowser-[0-9]+\.scope -- chromium-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for Chromium goes through launch-chromium-browser.sh"
# Arch's package names its entry chromium.desktop: the same wrapper, not the
# plain scope (no password store, no wallet guard).
stub xdg-settings 'echo chromium.desktop'
: > "$calls"
status=0; xdg-open https://example.org/page || status=$?
check '[[ $status -eq 0 ]] && grep -q "^chromium-browser --password-store=kwallet6 https://example.org/page$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web link for chromium.desktop goes through launch-chromium-browser.sh too ($(grep systemd-run "$calls" | head -1))"
# And there it runs as chromium - only where this machine has no real
# chromium-browser, which would otherwise be started.
rm -f "$bin/chromium-browser"
stub chromium
if ! command -v chromium-browser >/dev/null 2>&1; then
  : > "$calls"
  status=0; xdg-open https://example.org/page || status=$?
  check '[[ $status -eq 0 ]] && grep -qE "unit=app-buchhwin-chromium-[0-9]+\.scope -- chromium --password-store=kwallet6 https://example.org/page$" "$calls"' \
    "Arch: the link reaches chromium with Plasma's store ($(grep systemd-run "$calls" | head -1))"
fi
rm -f "$bin/chromium"
stub chromium-browser
stub xdg-settings 'echo com.brave.Browser.desktop'
# The handler's entry is looked up (a web app's runs the browser itself,
# below): in no data directory of the host's, which may or may not have
# KMail's and Kate's.
: > "$calls"
XDG_DATA_HOME="$sandbox/no-data" XDG_DATA_DIRS="$sandbox/no-data" xdg-open mailto:someone@example.org
check 'grep -qE "unit=app-buchhwin-org\.kde\.kmail2-[0-9]+\.scope -- " "$calls"' "another scheme takes its own handler's name"
printf 'x\n' > "$sandbox/doc.txt"
: > "$calls"
XDG_DATA_HOME="$sandbox/no-data" XDG_DATA_DIRS="$sandbox/no-data" xdg-open "$sandbox/doc.txt"
check 'grep -qE "unit=app-buchhwin-org\.kde\.kate-[0-9]+\.scope -- " "$calls"' "a file takes the handler of its type"
: > "$calls"
xdg-open "$sandbox/does-not-exist"
check '! grep -q systemd-run "$calls" && grep -q "^real-xdg-open $sandbox/does-not-exist$" "$calls"' "no handler known: the system xdg-open runs as it is"
: > "$calls"
xdg-open
check '! grep -q systemd-run "$calls" && grep -q "^real-xdg-open $" "$calls"' "no argument: handed on untouched"
# A web app's entry handles a scheme (Outlook's PWA is the mailto: handler
# here): its program is Brave itself, so the link goes through Brave's
# launcher with the entry's arguments - Plasma's store, the wallet check -
# not through the system xdg-open, which runs the entry's Exec as written.
apps="$sandbox/data/applications"
mkdir -p "$apps"
printf '%s\n' '[Desktop Entry]' 'Name=Mail' 'Exec=/opt/brave-bin/brave --profile-directory=Default --app-id=abcdef %U' \
  'MimeType=x-scheme-handler/mailto' '' '[Desktop Action compose]' 'Exec=/opt/brave-bin/brave --not-this-one' > "$apps/brave-abcdef-Default.desktop"
stub xdg-mime 'case "$*" in "query default x-scheme-handler/mailto") echo "$STUB_MAILTO" ;; "query filetype "*.html) echo text/html ;; "query filetype "*) echo text/plain ;; "query default text/html") echo brave-browser.desktop ;; "query default text/plain") echo org.kde.kate.desktop ;; *) echo "" ;; esac'
: > "$calls"
XDG_DATA_HOME="$sandbox/data" STUB_MAILTO=brave-abcdef-Default.desktop xdg-open mailto:someone@example.org
check 'grep -q "^brave-browser --password-store=kwallet6 --profile-directory=Default --app-id=abcdef mailto:someone@example.org$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a web app handling mailto: goes through launch-brave.sh with the entry's arguments ($(grep -E "^(brave|systemd-run)" "$calls" | head -2 | tr '\n' ' '))"
check 'grep -qE "unit=app-buchhwin-com\.brave\.Browser-[0-9]+\.scope -- " "$calls"' "in Brave's scope"
# Found in the system's applications too, after the user's.
mkdir -p "$sandbox/sysdata/applications"
mv "$apps/brave-abcdef-Default.desktop" "$sandbox/sysdata/applications/"
: > "$calls"
XDG_DATA_HOME="$sandbox/data" XDG_DATA_DIRS="$sandbox/nowhere:$sandbox/sysdata" STUB_MAILTO=brave-abcdef-Default.desktop \
  xdg-open mailto:someone@example.org
check 'grep -q "^brave-browser --password-store=kwallet6 --profile-directory=Default --app-id=abcdef mailto:someone@example.org$" "$calls"' \
  "an entry in XDG_DATA_DIRS is read the same way"
mv "$sandbox/sysdata/applications/brave-abcdef-Default.desktop" "$apps/"
# Every program services/launcher/LaunchLogic.js knows as a browser takes
# the launcher it names there: the two lists are one. Quoted arguments and
# %% come through as the specification says; the field codes go.
launcher_unit() {
  case $1 in
    launch-brave.sh) printf 'com\\.brave\\.Browser' ;;
    launch-chrome.sh) printf 'com\\.google\\.Chrome' ;;
    launch-chromium-browser.sh) printf 'chromium(\\\\x2dbrowser)?' ;;
    *) printf 'unknown-launcher' ;;
  esac
}
browser_table=$(sed -n '/^const BROWSER_PROGRAMS = {/,/^}/s/^ *"\([^"]*\)": *"\([^"]*\)",\{0,1\}$/\1 \2/p' "$project_dir/services/launcher/LaunchLogic.js")
check '[[ $(grep -c . <<<"$browser_table") -ge 7 ]]' "LaunchLogic's browser programs are read ($(grep -c . <<<"$browser_table"))"
while read -r program launcher; do
  [[ -n $program ]] || continue
  printf '%s\n' '[Desktop Entry]' "Exec=/opt/x/$program --app-id=a%%b \"--name=Web \\\"App\\\"\" %u" > "$apps/web-$program.desktop"
  : > "$calls"
  XDG_DATA_HOME="$sandbox/data" STUB_MAILTO="web-$program.desktop" xdg-open mailto:x@example.org
  unit=$(launcher_unit "$launcher")
  check 'grep -qE "unit=app-buchhwin-$unit-[0-9]+\.scope -- [^ ]+ --password-store=kwallet6 --app-id=a%b --name=Web \"App\" mailto:x@example.org$" "$calls"' \
    "a web app of $program goes through $launcher ($(grep systemd-run "$calls" | head -1))"
done <<<"$browser_table"
# Another program, or a browser's other build, is the entry's own business.
printf '%s\n' '[Desktop Entry]' 'Exec=/opt/x/brave-browser-beta --app-id=abcdef %U' > "$apps/beta-app.desktop"
: > "$calls"
XDG_DATA_HOME="$sandbox/data" STUB_MAILTO=beta-app.desktop xdg-open mailto:x@example.org
check 'grep -qE "unit=app-buchhwin-beta\\\\x2dapp-[0-9]+\.scope -- " "$calls" && ! grep -q -- "--password-store" "$calls"' \
  "a beta build's web app keeps its own entry ($(grep systemd-run "$calls" | head -1))"
# A local page as a file:// URL is a file: its type's handler, Brave here,
# through Brave's launcher, with the URL as it was given. Before, it asked
# for a file: scheme handler, found none, and the system xdg-open started
# the browser past its launcher.
printf '<p>x</p>\n' > "$sandbox/my page.html"
: > "$calls"
xdg-open "file://$sandbox/my%20page.html#top"
check 'grep -q "^brave-browser --password-store=kwallet6 file://$sandbox/my%20page.html#top$" "$calls" && ! grep -q real-xdg-open "$calls"' \
  "a file:// URL of a page goes through launch-brave.sh ($(grep -E "^(brave|real)" "$calls" | head -1))"
: > "$calls"
xdg-open "file://localhost$sandbox/my%20page.html?x=1"
check 'grep -q "^brave-browser --password-store=kwallet6 file://localhost$sandbox/my%20page.html?x=1$" "$calls"' \
  "with localhost and a query too"
: > "$calls"
xdg-open "file://$sandbox/no%20such%20page.html"
check '! grep -q systemd-run "$calls" && grep -q "^real-xdg-open file://$sandbox/no%20such%20page.html$" "$calls"' \
  "a file:// URL of nothing is handed on untouched"
stub xdg-mime 'case "$*" in "query default x-scheme-handler/mailto") echo org.kde.kmail2.desktop ;; "query filetype "*) echo text/plain ;; "query default text/plain") echo org.kde.kate.desktop ;; *) echo "" ;; esac'
# Without a known handler the system xdg-open starts one from here, so the
# shell's own settings are undone first (scripts/lib/app-env.sh), as
# launch-app.sh does for the rest.
cp "$sys/xdg-open" "$sandbox/xdg-open.kept"
printf '#!/bin/sh\nenv > "%s"\n' "$sandbox/xdg-environ" > "$sys/xdg-open"
env QS_ICON_THEME=breeze-dark MALLOC_ARENA_MAX=2 mesa_glthread=false GALLIUM_THREAD=0 \
  MALLOC_CONF=narenas:2 QT_WAYLAND_DISABLE_WINDOWDECORATION=1 QSG_DISTANCEFIELD_ANTIALIASING=gray BUCHHWIN_ICON_THEME_AUTO=1 \
  BUCHHWIN_APP_ENV_UNSET="MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO" \
  BUCHHWIN_APP_QPA_THEME=kde \
  xdg-open "$sandbox/does-not-exist"
check 'grep -qx "QT_QPA_PLATFORMTHEME=kde" "$sandbox/xdg-environ" && ! grep -qE "^(MALLOC_ARENA_MAX|MALLOC_CONF|mesa_glthread|GALLIUM_THREAD|QT_WAYLAND_DISABLE_WINDOWDECORATION|QSG_DISTANCEFIELD_ANTIALIASING|QS_ICON_THEME|BUCHHWIN_ICON_THEME_AUTO|BUCHHWIN_APP_ENV_UNSET)=" "$sandbox/xdg-environ"' \
  "no handler known: the system xdg-open gets the session's environment ($(grep -E "^(MALLOC|mesa|GALLIUM|QT_WAYLAND|QSG_|QS_|BUCHHWIN_ICON|QT_QPA)" "$sandbox/xdg-environ" | tr '\n' ' '))"
mv "$sandbox/xdg-open.kept" "$sys/xdg-open"

# ---- scripts/launch-alacritty.sh -------------------------------------------------
# The account's Alacritty with Settings > Terminal's opacity on top (for every
# cell background, not only the default one), in its own scope; the default
# without a setting, and nothing but a number in [0, 1] reaches the command
# line. A process of its own here: no display to name a daemon after, or the
# daemon switched off (terminal.alacrittyDaemon); the daemon's cases follow.
stub alacritty
cfg="$sandbox/alacritty-cfg"; mkdir -p "$cfg/buchhwin-shell"
: > "$calls"
env -u WAYLAND_DISPLAY -u DISPLAY XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh" -e true
check 'grep -qE "unit=app-buchhwin-Alacritty-[0-9]+\.scope -- alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true -e true$" "$calls" && ! grep -qE -- "--daemon| msg " "$calls"' \
  "Alacritty starts at the default 0.8 in its scope ($(grep systemd-run "$calls" | head -1))"
if command -v jq >/dev/null 2>&1; then
  printf '{ "terminal": { "opacity": 0.65, "alacrittyDaemon": false } }\n' > "$cfg/buchhwin-shell/settings.json"
  : > "$calls"
  WAYLAND_DISPLAY=wayland-9 XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh"
  check 'grep -q "^alacritty -o window.opacity=0.65 -o colors.transparent_background_colors=true$" "$calls" && ! grep -qE -- "--daemon| msg " "$calls"' \
    "the opacity follows Settings > Terminal, and the daemon switched off is a process of its own"
  printf '{ "terminal": { "opacity": "1; rm -rf ~", "alacrittyDaemon": false } }\n' > "$cfg/buchhwin-shell/settings.json"
  : > "$calls"
  WAYLAND_DISPLAY=wayland-9 XDG_CONFIG_HOME="$cfg" "$project_dir/scripts/launch-alacritty.sh"
  check 'grep -q "^alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true$" "$calls"' "anything but a number falls back to 0.8"
fi
check 'grep -q "Alacritty.desktop) exec \"\$project_dir/scripts/launch-alacritty.sh\"" "$project_dir/scripts/launch-default.sh"' \
  "the session's default terminal goes through it"
# --unit first, as for kitty: Settings > Updates' terminal when Alacritty is
# the session's (scripts/launch-terminal.sh, tests/launch-terminal-test.sh).
: > "$calls"
XDG_CONFIG_HOME="$sandbox/alacritty-none" "$project_dir/scripts/launch-alacritty.sh" --unit buchhwin-upgrade --hold -e true
run_line=$(grep "^systemd-run" "$calls" | head -1)
check '[[ $run_line == *"--unit=buchhwin-upgrade "*" -- alacritty -o window.opacity=0.8 -o colors.transparent_background_colors=true --hold -e true" && $run_line != *--scope* ]]' \
  "launch-alacritty.sh --unit runs Alacritty as that unit ($run_line)"

# ---- launch-alacritty.sh: one process for every window --------------------------
# The daemon is a stand-in that listens on the socket it is given, as long as
# the test runs; `msg` connects to it as the real one does, and fails where
# nothing listens. A runtime directory with a short path: a socket's has 107
# bytes. Every stand-in daemon is ended by the pid it wrote.
drt=$(mktemp -d /tmp/buchhwin-alacritty.XXXXXX)
daemon_pids="$sandbox/daemon-pids"
trap 'if [[ -r $daemon_pids ]]; then while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$daemon_pids"; fi; rm -rf -- "$sandbox" "$drt"' EXIT
mkdir -p "$drt/systemd" "$sandbox/home" "$sandbox/work/sub"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$drt/systemd/private"
cat > "$bin/alacritty" <<'STUB'
#!/bin/sh
printf 'alacritty %s\n' "$*" >> "$STUB_CALLS"
case $1 in
  --daemon)
    printf '%s\n' "$$" >> "$STUB_DAEMONS"
    printf 'daemon-cwd %s\n' "$PWD" >> "$STUB_CALLS"
    [ -z "${STUB_NO_SOCKET:-}" ] || exit 1
    exec python3 -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); s.listen(); time.sleep(60)' "$3" ;;
  msg)
    [ -z "${STUB_MSG_FAIL:-}" ] || exit 1
    exec python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).connect(sys.argv[1])' "$3" 2>/dev/null ;;
esac
exit 0
STUB
chmod +x "$bin/alacritty"
export STUB_CALLS="$calls" STUB_DAEMONS="$daemon_pids"
sock="$drt/buchhwin-alacritty-wayland-9-1700000000_42.sock"
state=${sock%.sock}
options="-o window.opacity=0.8 -o colors.transparent_background_colors=true"
# A key's start: from a directory of the caller's, on a display of a
# Hyprland instance, with no settings (the daemon is on by default).
key() {
  : > "$calls"; status=0
  (cd "$sandbox/work" && env WAYLAND_DISPLAY=wayland-9 HYPRLAND_INSTANCE_SIGNATURE="${key_instance:-c0ffee_1700000000_42}" \
     XDG_RUNTIME_DIR="$drt" XDG_CONFIG_HOME="$sandbox/alacritty-none" HOME="$sandbox/home" \
     "$project_dir/scripts/launch-alacritty.sh" "$@" </dev/null) || status=$?
}
alone() { grep -qE "unit=app-buchhwin-Alacritty-[0-9]+\.scope -- alacritty $options$1\$" "$calls" && ! grep -q -- "--daemon" "$calls"; }
key -e true
check '[[ $status -eq 0 ]] && grep -qE "^systemd-run --user --scope .*--unit=app-buchhwin-Alacritty-[0-9]+\.scope -- alacritty --daemon --socket $sock $options$" "$calls"' \
  "the first window starts the daemon in Alacritty's scope, its socket named after the display and the instance ($(grep -- "--daemon" "$calls" | head -1))"
check 'grep -qx "daemon-cwd $sandbox/home" "$calls"' "from the home directory: it holds no one's working directory"
check 'grep -qx "alacritty msg --socket $sock create-window --working-directory $sandbox/work $options -e true" "$calls"' \
  "and the window is asked of it, in the caller's directory ($(grep " msg " "$calls"))"
daemon_pid=$(cat "$state.pid" 2>/dev/null || true)
check '[[ -n $daemon_pid && -d /proc/$daemon_pid ]] && ! ls -l "/proc/$daemon_pid/fd" 2>/dev/null | grep -q "\.lock$"' \
  "the daemon runs on, without the lock's descriptor"
key
check '[[ $status -eq 0 ]] && ! grep -qE -- "--daemon|^systemd-run" "$calls" && grep -qx "alacritty msg --socket $sock create-window --working-directory $sandbox/work $options" "$calls"' \
  "the next window goes to the same daemon, no process of its own ($(tr '\n' ' ' < "$calls"))"
key --hold --title "System upgrade" -e sh -c 'echo hi'
check 'grep -qx "alacritty msg --socket $sock create-window --working-directory $sandbox/work $options --hold --title System upgrade -e sh -c echo hi" "$calls"' \
  "--hold, the title and the command after -e reach the window ($(grep " msg " "$calls"))"
key --working-directory sub
check 'grep -qx "alacritty msg --socket $sock create-window --working-directory $sandbox/work/sub $options" "$calls"' \
  "a relative working directory goes along, absolute ($(grep " msg " "$calls"))"
key --config-file /x.toml -e true
check '[[ $status -eq 0 ]] && ! grep -q " msg " "$calls" && alone " --config-file /x.toml -e true"' \
  "an option only a new process knows: a process of its own ($(grep systemd-run "$calls" | head -1))"
key --working-directory "$sandbox/missing"
check '! grep -q " msg " "$calls" && alone " --working-directory $sandbox/missing"' \
  "a working directory that is not there: a new process, which says so itself"
key --unit buchhwin-upgrade --hold -e true
check '! grep -q " msg " "$calls" && grep -q -- "--unit=buchhwin-upgrade " "$calls"' "--unit: the window is that unit's own process"
export STUB_MSG_FAIL=1
key -e true
unset STUB_MSG_FAIL
check '[[ $status -eq 0 ]] && alone " -e true" && [[ -d /proc/$daemon_pid ]]' \
  "a daemon that is alive but does not answer is never replaced: this window is a process of its own ($(tr '\n' ' ' < "$calls"))"
kill "$daemon_pid" 2>/dev/null || true
for _ in {1..50}; do [[ -d /proc/$daemon_pid ]] || break; sleep 0.05; done
key -e true
check '[[ $status -eq 0 && -S $sock ]] && grep -q -- "alacritty --daemon --socket $sock" "$calls" && grep -q " msg --socket $sock create-window" "$calls" && [[ $(cat "$state.pid" 2>/dev/null) != "$daemon_pid" ]]' \
  "a daemon that is gone is started again, its socket left behind replaced ($(tr '\n' ' ' < "$calls"))"
kill "$(cat "$state.pid" 2>/dev/null)" 2>/dev/null || true
export STUB_NO_SOCKET=1
key -e true
check '[[ $status -eq 0 && -e $state.failed ]] && grep -q -- "alacritty --daemon" "$calls" && grep -qE "Alacritty-[0-9]+\.scope -- alacritty $options -e true$" "$calls"' \
  "a daemon that never comes up: the window is a process of its own ($(tr '\n' ' ' < "$calls"))"
key -e true
check 'alone " -e true"' "and no daemon is tried again in this login"
unset STUB_NO_SOCKET
# A file it cannot write - the lock, here a directory in its place, or
# anything in a full runtime directory - ends no start under set -e: the
# window is a process of its own (another login's names, no daemon yet).
key_instance=c0ffee_1700000001_43
mkdir -p "$drt/buchhwin-alacritty-wayland-9-1700000001_43.lock"
key -e true 2>/dev/null
check '[[ $status -eq 0 ]] && alone " -e true"' \
  "a lock it cannot open: the window is a process of its own (status $status: $(tr '\n' ' ' < "$calls"))"
unset key_instance

if (( failures )); then printf 'TESTS FAILED launch-app (%d failed)\n' "$failures"; exit 1; fi
printf 'TESTS PASSED launch-app\n'
