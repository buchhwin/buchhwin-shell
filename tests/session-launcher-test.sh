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
cp "$project_dir/scripts/wallet-unlock.sh" "$project/scripts/"
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

# Hyprland built into the home directory (openSUSE Leap) comes first on PATH;
# without it the packaged one is used and PATH is left alone.
prefix="$home/.local/opt/buchhwin-hyprland"
mkdir -p "$prefix/bin"
printf '#!/bin/sh\nprintf "%%s %%s\\n" "built-start-hyprland" "$*" >> "%s"\n' "$calls" > "$prefix/bin/start-hyprland"
chmod +x "$prefix/bin/start-hyprland"
launch; check 'grep -q "^built-start-hyprland -- --config .*hyprland.lua" "$calls" && ! grep -q "^start-hyprland " "$calls"' \
  "the home-built Hyprland is used when it is there"
rm -rf "$home/.local/opt"
launch; check 'grep -q "^start-hyprland " "$calls"' "the packaged Hyprland otherwise"

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
check 'grep -q "^systemctl --user unmask --runtime app-geoclue\\\\x2ddemo\\\\x2dagent@autostart.service app-sealertauto@autostart.service app-org.freedesktop.problems.applet@autostart.service app-print\\\\x2dapplet@autostart.service$" "$calls"' "autostart units unmasked at logout"
check '[[ $(tail -n1 "$calls") == "systemctl --user stop buchhwin-shell-session.target" ]]' "session target stopped last"

# Autostart skip list.
source "$project_dir/scripts/lib/autostart-skip.sh"
check '[[ $(autostart_skip_units | paste -sd" ") == "app-geoclue\\x2ddemo\\x2dagent@autostart.service app-sealertauto@autostart.service app-org.freedesktop.problems.applet@autostart.service app-print\\x2dapplet@autostart.service" ]]' "generated unit names"

# session-init.sh: environment and portal before the shell, masks before autostart.
# The runtime directory is the sandbox's too: the real one has a kwallet socket
# on a machine that ran a KDE login, and the real bus has a secret service.
runtime="$sandbox/run"
mkdir -p "$runtime"
stub busctl 'exit 0'
init() {
  : > "$calls"
  env -u BUCHHWIN_NESTED HOME="$home" XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$runtime" "$@" \
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
check 'grep -q "XDG_SESSION_TYPE" "$calls" && grep -q "QT_QPA_PLATFORM " "$calls"' \
  "the session type and the Qt platform reach the user manager (ksecretd reads them)"
check '! grep -q "plasma-kwallet-pam" "$calls"' "no kwallet socket, no kwallet step"

# KWallet: with the PAM socket the unit runs, and the mark says what the bus
# says - not merely that socat ran.
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$runtime/kwallet5.socket"
# `list` says who owns the names (the secret service and the Secret portal
# backend are the same ksecretd); `get-property` says whether the wallet is open.
owned='printf "NAME PID PROCESS\norg.freedesktop.secrets 42 ksecretd\norg.freedesktop.impl.portal.desktop.kwallet 42 ksecretd\n"'
stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"
init
kwallet=$(line_of "systemctl --user start plasma-kwallet-pam.service")
check '[[ -n $kwallet && $kwallet -lt $(line_of "systemctl --user restart xdg-desktop-portal.service") ]]' \
  "the wallet is handed the login before the portal restart"
check '[[ $(line_of "busctl --user list") -lt $(line_of "systemctl --user restart xdg-desktop-portal.service") ]]' \
  "the portal is only restarted once the bus has been asked for the Secret backend"
check 'grep -q "secret service and its portal backend on the bus" "$timeline"' "the backend's arrival is marked"
check 'grep -q "kwallet unlocked: open (already)" "$timeline"' "unlocked only when the bus has the secret service and the wallet is open"
check '! grep -qE -- "--auto-start=yes|status org.freedesktop.secrets" "$calls"' "the check never activates a second ksecretd"
check 'grep -q -- "--auto-start=no .*get-property org.freedesktop.secrets" "$calls"' "the lock state is read without activating anything"
check '[[ $(line_of "get-property org.freedesktop.secrets") -gt $(line_of "systemctl --user restart xdg-desktop-portal.service") ]]' \
  "the wallet is asked after the portal work, before autostart"
check '[[ $(line_of "get-property org.freedesktop.secrets") -lt $(line_of "systemctl --user start buchhwin-shell-autostart.target") ]]' \
  "nothing autostarts before the wallet step has run"
# The owner is there but the wallet stayed shut (what session-check found on
# 2026-10-09): the step asks the service to unlock, once, without auto-start.
# Answered (the service held the login password): the mark says so.
stub busctl "case \"\$*\" in *Unlock*) touch \"\$STUB_UNLOCKED\"; printf 'ao 1 \"/org/freedesktop/secrets/collection/kdewallet\" o \"/\"\n' ;; *get-property*) if [ -e \"\$STUB_UNLOCKED\" ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
rm -f "$sandbox/unlocked"
STUB_UNLOCKED="$sandbox/unlocked" init
check 'grep -q "kwallet unlocked: open (after unlock)" "$timeline"' "a wallet the hand-over left shut is asked open"
check '[[ $(grep -c -- "--auto-start=no .*Unlock ao 1 /org/freedesktop/secrets/collection/kdewallet" "$calls") -eq 1 ]]' "asked once, without activating anything"
# The service needs a password: the prompt is followed, once, so the dialog
# appears at login and not under the first application that asks.
stub busctl "case \"\$*\" in *Unlock*) printf 'ao 0 o \"/org/freedesktop/secrets/prompt/p1\"\n' ;; *\"Secret.Prompt Prompt\"*) touch \"\$STUB_PROMPTED\" ;; *get-property*) if [ -e \"\$STUB_PROMPTED\" ]; then echo 'b false'; else echo 'b true'; fi ;; *) $owned ;; esac"
rm -f "$sandbox/prompted"
STUB_PROMPTED="$sandbox/prompted" init
check 'grep -q "kwallet unlocked: open (after prompt" "$timeline"' "a prompt the login needs is followed"
check '[[ $(grep -c -- "--auto-start=no .*/org/freedesktop/secrets/prompt/p1 org.freedesktop.Secret.Prompt Prompt s " "$calls") -eq 1 ]]' "the prompt is followed once, without activating anything"
# Not answered (no prompt offered, no password): LOCKED, and no second attempt.
stub busctl "case \"\$*\" in *get-property*) echo 'b true' ;; *) $owned ;; esac"
init
check 'grep -q "kwallet LOCKED: locked (no prompt offered)" "$timeline"' "an owner with a locked wallet is not called unlocked"
check '[[ $(grep -c "Unlock ao" "$calls") -eq 1 ]]' "one ask, then the truth"
# The wallet step does not depend on the autostart setting: Brave started by
# hand needs the wallet as much as an autostarted one.
printf '{ "autostart": { "system": false } }\n' > "$home/.config/buchhwin-shell/settings.json"
stub busctl "case \"\$*\" in *get-property*) echo 'b false' ;; *) $owned ;; esac"
init
check 'grep -q "kwallet unlocked: open (already)" "$timeline"' "autostart off: the wallet is still checked"
check '! grep -q "mask\|buchhwin-shell-autostart.target" "$calls"' "autostart off: no masks, no autostart target"
rm "$home/.config/buchhwin-shell/settings.json"
stub busctl 'printf "NAME PID PROCESS\norg.freedesktop.secrets - -\n"'
# No ksecretd running (the host's real one must not stretch the wait).
stub pgrep 'exit 1'
init
check 'grep -q "secret service NOT on the bus after 3 s" "$timeline" && grep -q "kwallet NOT available: no service" "$timeline"' \
  "an activatable but unowned name is not an unlocked wallet"
check 'grep -q "^pgrep -u [0-9]* -x ksecretd" "$calls"' "a ksecretd still registering is looked for before giving up"
rm -f "$bin/pgrep"
rm -f "$runtime/kwallet5.socket"
stub busctl 'exit 0'

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
BUCHHWIN_DISTRO=fedora "$project_dir/install/system-install.sh" --root "$root" >/dev/null
wrapper="$root/usr/local/bin/buchhwin-shell-session"
check '[[ -x $wrapper ]] && cmp -s "$wrapper" "$project_dir/session/buchhwin-shell-session-wrapper"' "wrapper installed executable"
check 'grep -qx "Exec=/usr/local/bin/buchhwin-shell-session" "$root/usr/share/wayland-sessions/buchhwin-shell.desktop"' "session entry runs the wrapper"
check '[[ -f $root/etc/pam.d/buchhwin-lock && -f $root/etc/pam.d/buchhwin-lock-password ]]' "PAM services installed"
printf 'keep' > "$root/etc/pam.d/buchhwin-lock"
"$project_dir/install/system-install.sh" --root "$root" >/dev/null
check '[[ $(cat "$root/etc/pam.d/buchhwin-lock") == keep ]]' "existing PAM files kept"
check 'grep -q "include *password-auth" "$root/etc/pam.d/buchhwin-lock-password"' "Fedora: password-auth"
suse_root="$sandbox/suse-root"
BUCHHWIN_DISTRO=opensuse-leap "$project_dir/install/system-install.sh" --root "$suse_root" >/dev/null
check 'grep -q "include *common-auth" "$suse_root/etc/pam.d/buchhwin-lock"' "openSUSE: the lock includes common-auth"
check '! grep -v "^#" "$suse_root/etc/pam.d/buchhwin-lock-password" | grep -q "pam_fprintd\|system-auth\|password-auth"' \
  "openSUSE: password only, nothing from Fedora"
status=0; BUCHHWIN_DISTRO=opensuse-leap "$project_dir/install/system-install.sh" --fingerprint-lid >/dev/null 2>"$sandbox/stderr.log" || status=$?
check '[[ $status -eq 1 ]] && grep -q "needs authselect" "$sandbox/stderr.log"' "openSUSE: --fingerprint-lid refuses"
# Arch has system-auth like Fedora but no password-auth: by the stack alone it
# would get Fedora's files, and the password service would include nothing.
arch_root="$sandbox/arch-root"
mkdir -p "$arch_root/etc/pam.d" && : > "$arch_root/etc/pam.d/system-auth"
BUCHHWIN_DISTRO=arch "$project_dir/install/system-install.sh" --root "$arch_root" >/dev/null
check 'grep -q "include *system-auth" "$arch_root/etc/pam.d/buchhwin-lock"' "Arch: the lock includes system-auth"
# The reader goes into this file, but only on the user's word (Settings >
# Lock Screen offers the command); the shipped file has no active line.
check '! grep -v "^#" "$arch_root/etc/pam.d/buchhwin-lock" | grep -q pam_fprintd' "Arch: no reader in the shipped lock service"
check '! grep -v "^#" "$arch_root/etc/pam.d/buchhwin-lock-password" | grep -q "include\|pam_fprintd"' \
  "Arch: password only, no password-auth and no other stack"
check 'grep -q "pam_unix.so *try_first_pass" "$arch_root/etc/pam.d/buchhwin-lock-password"' "Arch: the password is pam_unix's"
# A derivative under sudo: no BUCHHWIN_DISTRO (sudo drops it), an os-release
# distro_detect refuses, so the name says "fedora" - the stack has to decide.
derivative_root="$sandbox/derivative-root"
mkdir -p "$derivative_root/etc/pam.d" && : > "$derivative_root/etc/pam.d/system-auth"
printf 'ID=endeavouros\nID_LIKE=arch\n' > "$sandbox/os-release-derivative"
env -u BUCHHWIN_DISTRO BUCHHWIN_OS_RELEASE="$sandbox/os-release-derivative" \
  "$project_dir/install/system-install.sh" --root "$derivative_root" >/dev/null
check 'cmp -s "$derivative_root/etc/pam.d/buchhwin-lock-password" "$project_dir/session/pam/buchhwin-lock-password.arch"' \
  "Arch derivative: system-auth without password-auth gets the .arch password service"
check 'cmp -s "$derivative_root/etc/pam.d/buchhwin-lock" "$project_dir/session/pam/buchhwin-lock.arch"' \
  "Arch derivative: and the .arch lock service"
status=0; BUCHHWIN_DISTRO=arch "$project_dir/install/system-install.sh" --fingerprint-lid >/dev/null 2>"$sandbox/stderr.log" || status=$?
check '[[ $status -eq 1 ]] && grep -q "needs authselect" "$sandbox/stderr.log"' "Arch: --fingerprint-lid refuses"
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
