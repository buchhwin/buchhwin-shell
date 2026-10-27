#!/usr/bin/env bash
set -uo pipefail

# Login session setup, started once by the Hyprland config:
#   session-init.sh SHELL_PATH
# Makes the compositor environment available to D-Bus/systemd activated KDE and
# desktop services, starts the shell (scripts/start-shell.sh SHELL_PATH) as
# soon as that is done, and then does the slow part: waits for the secret
# service, restarts the portal, opens the wallet and starts the autostart
# apps. The shell starts first on purpose - a slow portal used to keep the
# screen black - so its Qt registration with the portal can be dropped by the
# restart; it uses no portal, and a restarted portal ends every registration
# anyway. Steps that fail are reported and skipped; the shell starts in any
# case. Nested test sessions never run this script (they start
# start-shell.sh directly).
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_path=${1:-}
shell_started=0

# Login timeline, so a slow start can be told apart afterwards
# (scripts/session-check.sh prints it). The previous login stays as .old.
startup_log="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/startup.log"
mkdir -p -- "$(dirname -- "$startup_log")" 2>/dev/null || true
[[ -e $startup_log ]] && mv -f -- "$startup_log" "$startup_log.old" 2>/dev/null
# The clock from bash itself: two `date` processes per mark were thirty
# forks in a login that is waiting for the shell. EPOCHREALTIME is seconds
# and microseconds, with the locale's decimal point - only the digits count.
start_us=${EPOCHREALTIME//[!0-9]/}
mark() {
  local now=${EPOCHREALTIME//[!0-9]/}
  printf '%(%H:%M:%S)T +%5sms %s\n' -1 "$(( (${now:-0} - ${start_us:-0}) / 1000 ))" "$*" >> "$startup_log" 2>/dev/null || true
}
# The compositor by its signature, and its pid from the lock file beside its
# socket (pid first, then its display).
hyprland_pid=""
read -r hyprland_pid 2>/dev/null <"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/hyprland.lock" || true
mark "session-init started (Hyprland ${HYPRLAND_INSTANCE_SIGNATURE:-unknown}${hyprland_pid:+, pid $hyprland_pid})"

start_shell() {
  (( shell_started )) && return 0
  shell_started=1
  [[ -n $shell_path ]] || return 0
  setsid -f "$project_dir/scripts/start-shell.sh" "$shell_path" </dev/null >/dev/null 2>&1
  mark "shell started"
}
trap 'start_shell; mark "session-init finished"' EXIT

step() {
  local label=$1
  shift
  "$@" || printf 'session-init: step failed (%s): %s\n' "$?" "$*" >&2
  mark "$label"
}

if [[ ${BUCHHWIN_NESTED:-0} == 1 ]]; then
  printf 'session-init: nested session, only starting the shell\n' >&2
  exit 0
fi

# Cursor theme from the shell settings, before the environment is exported.
settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
# A broken settings file must not stop the session setup below - and "broken"
# includes *empty*, which is what a crash during an atomic write leaves behind.
# jq exits 0 on a zero-byte file and prints nothing, so the `||` never fired
# and two empty variables went into the systemd user environment and the D-Bus
# activation environment for the whole login. Truncated-but-nonempty JSON does
# hit the `||`; only the empty case slipped through, so the value is checked
# rather than the exit status.
XCURSOR_THEME=""
XCURSOR_SIZE=""
if command -v jq >/dev/null 2>&1 && [[ -s $settings ]]; then
  XCURSOR_THEME=$(jq -r '.appearance.cursorTheme // "breeze_cursors"' "$settings" 2>/dev/null) || XCURSOR_THEME=""
  XCURSOR_SIZE=$(jq -r '.appearance.cursorSize // 24' "$settings" 2>/dev/null) || XCURSOR_SIZE=""
fi
[[ -n $XCURSOR_THEME && $XCURSOR_THEME != null ]] || XCURSOR_THEME=breeze_cursors
[[ $XCURSOR_SIZE =~ ^[0-9]+$ ]] || XCURSOR_SIZE=24
export XCURSOR_THEME XCURSOR_SIZE
# Not waited for. Hyprland answers it from its main loop, which at this point
# is still modesetting the outputs: ~150 ms of the 170 before "cursor set" on
# 19.10., with the shell waiting behind it. Nothing below needs the answer
# (the variables above are what the import hands on), and the shell sends the
# same call itself once its settings are loaded (AppearanceService).
hyprctl setcursor "$XCURSOR_THEME" "$XCURSOR_SIZE" >/dev/null 2>&1 &
# Marked on its own. The first two timelines put 1.1-2.2 s between "session-init
# started" and "environment imported", and that gap held three things: jq,
# the hyprctl call above and the systemd import below. The user manager was
# idle through both logins (its startup had finished 2.3 s before
# session-init began), so the import is not the obvious suspect it looked like;
# this mark is what tells them apart.
mark "cursor set"

# PAM_KWALLET5_LOGIN is what pam_kwallet_init (plasma-kwallet-pam.service, below)
# reads to hand the session environment to the ksecretd that pam_kwallet5
# started with the login password; without it in the user manager's
# environment the unit does nothing and the wallet never comes up.
#
# XDG_SESSION_TYPE and QT_QPA_PLATFORM go with them because pam_kwallet_init
# hands ksecretd *this* environment (`env | socat`), and ksecretd is a Qt
# program: Plasma's user manager has both, this session's did not, and the
# ksecretd of a buchhwin-shell login stayed alive but never reached the bus -
# so kwalletd6 asked for the password later. The launcher exports
# QT_QPA_PLATFORM; the session type is a Wayland one whatever SDDM said.
export XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-wayland}
session_variables=(
  DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP DESKTOP_SESSION XDG_SESSION_TYPE
  QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME XCURSOR_THEME XCURSOR_SIZE
  XDG_CONFIG_DIRS PAM_KWALLET5_LOGIN
)
step "environment imported" systemctl --user import-environment "${session_variables[@]}"
step "D-Bus activation environment" dbus-update-activation-environment --systemd "${session_variables[@]}"

step "session target" systemctl --user start buchhwin-shell-session.target

# KWallet. pam_kwallet5 (in common-auth and common-session on openSUSE, which
# /etc/pam.d/sddm includes; directly in /etc/pam.d/sddm on Arch) started
# `ksecretd --pam-login` with the hashed login password at the SDDM login;
# that ksecretd waits on /run/user/$UID/kwallet5.socket for the session's
# environment, and the thing that hands it over is pam_kwallet_init
# (/usr/libexec on Fedora and openSUSE, /usr/lib on Arch), which Plasma runs
# from plasma-kwallet-pam.service. The unit is `static` and only PartOf
# graphical-session.target, so nothing pulls it in outside a Plasma session.
# Started here, right after the environment import, because the ksecretd it
# wakes is both the secret service and the Secret portal's backend.
# Skipped without the unit or the socket.
#
# One daemon, one wallet: ksecretd owns org.kde.ksecretd, the portal backend
# org.freedesktop.impl.portal.desktop.kwallet and, on Fedora and openSUSE,
# org.freedesktop.secrets. On Arch gnome-keyring usually holds that last name
# (pam_gnome_keyring in /etc/pam.d/sddm); it stays, for what keeps its
# secrets there, and the wallet is reached through ksecretd's own name
# (scripts/wallet-unlock.sh). kwalletd6 is a compatibility shim over the same
# service (KF 6.16), not a second wallet with its own lock - whatever asks
# org.kde.kwalletd6 ends up here.
# Asked once, for the hand-over here and for the wait and the wallet step
# below: each `systemctl --user cat` cost ~20 ms, the first of them before
# the shell had started.
pam_wallet=0
if [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kwallet5.socket" ]] \
   && systemctl --user cat plasma-kwallet-pam.service >/dev/null 2>&1; then
  pam_wallet=1
fi
if (( pam_wallet )); then
  step "kwallet handed the login" systemctl --user start plasma-kwallet-pam.service
fi
# Citrix's daemons leave their pid locks behind when they are killed (a logout,
# a shutdown), and a lock whose pid is gone or now another program's starts
# no daemon: Citrix Workspace stays white. Before the shell, which can start
# Citrix; locks of a running Citrix process stay (scripts/citrix-locks.py).
if [[ -d $HOME/.ICAClient/.tmp ]]; then
  moved_locks=$(python3 "$project_dir/scripts/citrix-locks.py" 2>&1)
  mark "citrix locks checked${moved_locks:+: ${moved_locks//$'\n'/, }}"
fi
# The shell starts before the portal work: it only needs the environment above,
# and waiting for portal units (which can take a long time on a cold boot) used
# to leave the screen black until they were done.
start_shell

# The portal restart below must find the Secret backend on the bus. On Fedora
# and openSUSE the backend's name has no D-Bus service file, so a portal that
# starts before ksecretd has registered has no Secret portal for the whole
# session; on Arch it has one (Exec=/usr/bin/ksecretd), so the same early
# restart could activate a second ksecretd that never got the password. Up to
# three seconds, ten while the ksecretd PAM started is running but has not
# registered yet, and the mark says how long it took. The bus driver's
# NameHasOwner starts nothing; `status`, or any plain call to an activatable
# name, would start a second ksecretd without the password
# (org.kde.secretservicecompat has a service file). It costs ~2-4 ms where
# `busctl list`, which looked up every name's process, took 10-25 ms - up to
# three of them in each step of this wait.
name_owned() {
  [[ $(busctl --user --auto-start=no --no-pager --timeout=3 call org.freedesktop.DBus /org/freedesktop/DBus \
         org.freedesktop.DBus NameHasOwner s "$1" 2>/dev/null) == "b true" ]]
}
wait_for_secrets() {
  (( pam_wallet )) || return 0
  local waited=0 limit=3000
  while (( waited < limit )); do
    { name_owned org.kde.ksecretd || name_owned org.freedesktop.secrets; } \
      && name_owned org.freedesktop.impl.portal.desktop.kwallet && break
    sleep 0.1
    waited=$(( waited + 100 ))
    if (( waited == 3000 )) && pgrep -u "$(id -u)" -x ksecretd >/dev/null 2>&1; then
      limit=10000
    fi
  done
  if name_owned org.freedesktop.impl.portal.desktop.kwallet; then
    mark "secret service and its portal backend on the bus (${waited} ms)"
  else
    mark "secret service NOT on the bus after $(( waited / 1000 )) s ($(pgrep -c -x ksecretd 2>/dev/null || echo 0) ksecretd running)"
  fi
}
wait_for_secrets
step "portal (Hyprland)" timeout 20 systemctl --user start xdg-desktop-portal-hyprland.service
# A portal left over from an earlier session (or activated before the
# environment import above) keeps its old desktop routing; restart it so Secret
# requests reach KWallet like in Plasma.
step "portal restarted" timeout 20 systemctl --user restart xdg-desktop-portal.service

# The wallet itself, after the shell is up and before anything that stores
# secrets can start: the autostart entries below, and Brave through
# scripts/launch-brave.sh. Handed the login password, ksecretd opens the
# wallet by itself; when it has not, scripts/wallet-unlock.sh asks it to and
# follows the prompt, so the one password dialog of this login appears now,
# on a desktop, rather than later under whichever application asked first.
# Chromium treats a wallet it cannot open as gone for good and encrypts with a
# fallback key - a logout from everything on the next session switch - which
# is why this waits, and why launch-brave.sh refuses a shut wallet.
wallet_step() {
  (( pam_wallet )) || return 0
  local tool="$project_dir/scripts/wallet-unlock.sh" result status
  [[ -x $tool ]] || { mark "kwallet: scripts/wallet-unlock.sh missing, wallet state unknown"; return 0; }
  result=$("$tool" ensure --prompt --wait 3 --timeout 90 2>/dev/null)
  status=$?
  case $status in
    0) mark "kwallet unlocked: $result" ;;
    1) mark "kwallet LOCKED: $result - applications that store secrets will ask for the password; Brave refuses to start" ;;
    2) mark "kwallet NOT available: $result" ;;
    *) mark "kwallet: $result" ;;
  esac
}
wallet_step

# Standard XDG autostart (entries matching XDG_CURRENT_DESKTOP, e.g. KDE
# Connect, calendar reminders) unless turned off in Settings > Autostart.
if ! command -v jq >/dev/null 2>&1 || [[ ! -r $settings ]] || [[ $(jq -r '.autostart.system' "$settings" 2>/dev/null || echo true) != false ]]; then
  # Entries that are useless here (scripts/lib/autostart-skip.sh) are kept
  # out of this session. install/install.sh links a drop-in for each
  # (systemd/autostart-skip.conf: a condition on XDG_CURRENT_DESKTOP, so the
  # unit is skipped here and runs in Plasma), which needs nothing at login.
  # Without it the units are masked for this user manager run only, and the
  # session launcher unmasks them at logout - but a mask makes the user
  # manager reload (306 ms on 19.10., before any autostart app could start),
  # so only entries this system has are masked: three of the four names were
  # masked on Arch for entries that do not exist there.
  # shellcheck source=lib/autostart-skip.sh
  source "$project_dir/scripts/lib/autostart-skip.sh"
  mapfile -t listed_units < <(autostart_skip_units)
  autostart_dirs=("${XDG_CONFIG_HOME:-$HOME/.config}")
  IFS=: read -r -a config_dirs <<<"${XDG_CONFIG_DIRS:-/etc/xdg}"
  autostart_dirs+=("${config_dirs[@]}")
  skipped_units=()
  for index in "${!BUCHHWIN_AUTOSTART_SKIP[@]}"; do
    unit=${listed_units[index]:-}
    [[ -n $unit ]] || continue
    [[ -e ${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$unit.d/buchhwin-shell.conf ]] && continue
    for dir in "${autostart_dirs[@]}"; do
      if [[ -n $dir && -e $dir/autostart/${BUCHHWIN_AUTOSTART_SKIP[index]}.desktop ]]; then
        skipped_units+=("$unit")
        break
      fi
    done
  done
  if (( ${#skipped_units[@]} )); then
    step "autostart entries masked" systemctl --user mask --runtime "${skipped_units[@]}"
    systemctl --user stop "${skipped_units[@]}" 2>/dev/null || true
  fi
  # xdg-desktop-autostart.target refuses manual starts; this target wants it.
  step "XDG autostart" systemctl --user start buchhwin-shell-autostart.target
fi
step "polkit agent" systemctl --user start plasma-polkit-agent.service

# A previous desktop setup installs this generic Hyprland service globally via
# graphical-session.target. It owns the old dwl-style bar. Stop it only for this
# session; never disable or delete the user's legacy unit.
systemctl --user stop buchhwin-shell.service 2>/dev/null || true
