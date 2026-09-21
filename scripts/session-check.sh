#!/usr/bin/env bash
set -uo pipefail

# Check a running buchhwin-shell login session and print a short report.
# Read-only: it changes nothing. Run it from a terminal inside the session:
#   ~/.local/share/buchhwin-shell/scripts/session-check.sh
project_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)
# shellcheck source=lib/hypr.sh
source "$project_dir/scripts/lib/hypr.sh"
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
settings="$config_home/buchhwin-shell/settings.json"
shell_path=${BUCHHWIN_SHELL_PATH:-$HOME/.local/share/buchhwin-shell}
failures=0
warnings=0

ok() { printf '  \033[32mok\033[0m      %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m    %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf '  \033[31merror\033[0m   %s\n' "$*"; failures=$((failures + 1)); }
section() { printf '\n%s\n' "$*"; }
setting() { jq -r "$1" "$settings" 2>/dev/null; }
# running NAME PATTERN: a process with executable NAME whose command line
# matches PATTERN (exact names avoid matching shells that mention the text).
running() {
  local pid
  for pid in $(pgrep -u "$(id -u)" -x "$1" 2>/dev/null); do
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -qE -- "${2:-.}" && return 0
  done
  return 1
}

section "Session"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then ok "Hyprland is running ($(hyprctl version -j 2>/dev/null | jq -r '.tag // .version // "?"'))"; else fail "no Hyprland session (HYPRLAND_INSTANCE_SIGNATURE is missing)"; exit 1; fi
[[ ${XDG_CURRENT_DESKTOP:-} == buchhwin-shell:Hyprland ]] && ok "XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP" || warn "XDG_CURRENT_DESKTOP is '${XDG_CURRENT_DESKTOP:-}' (expected buchhwin-shell:Hyprland)"
if hypr_is_lua; then
  ok "configuration: Lua"
elif [[ ${BUCHHWIN_HYPR_CONFIG_FALLBACK:-0} == 1 ]]; then
  warn "configuration: hyprland.conf (the Lua start failed; see the display manager log)"
else
  ok "configuration: hyprland.conf"
fi
command -v hyprland-dialog >/dev/null 2>&1 && ok "hyprland-guiutils installed" || warn "hyprland-guiutils is missing (Hyprland dialogs; sudo dnf install hyprland-guiutils)"
errors=$(hyprctl configerrors 2>/dev/null | grep -v '^$' || true)
[[ -z $errors ]] && ok "no Hyprland configuration errors" || fail "Hyprland reports: $errors"

section "Shell"
if quickshell ipc --path "$shell_path" show >/dev/null 2>&1; then
  ok "Quickshell responds ($(quickshell ipc --path "$shell_path" show | grep -c '^target') IPC targets)"
else
  fail "Quickshell is not running or not responding (Super+Ctrl+R restarts it)"
fi
# A shell started without HYPRLAND_INSTANCE_SIGNATURE comes up blind: Settings
# > Displays stays empty, the saved scaling is never applied and no dispatch
# arrives. It looks like a broken page rather than a missing variable, so it is
# named here.
#
# The log has to be readable before its silence means anything. It used to be
# read with `2>/dev/null` into a grep, so a shell that was not running at all
# produced no output, no match, and an "ok" four lines under "Quickshell is not
# running" - the same shape as the "unlocked by PAM" line further down, which
# this file already had to learn once.
if shell_log=$(quickshell log --path "$shell_path" 2>/dev/null) && [[ -n $shell_log ]]; then
  if grep -q 'HYPRLAND_INSTANCE_SIGNATURE is unset' <<<"$shell_log"; then
    fail "the shell has no Hyprland connection (started outside the session; Super+Ctrl+R restarts it)"
  else
    ok "shell is connected to Hyprland"
  fi
else
  warn "could not read the shell log, so the Hyprland connection is unknown"
fi
# Which Hyprland dialect the shell settled on. Guessing wrong is silent and
# total - every `keyword` is rejected by a Lua config manager, so the animation
# mode, blur, rounding, gaps and the cursor stop reaching the compositor for
# the whole session and nothing says so.
dialect=$(quickshell ipc --path "$shell_path" call displays get 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("dialect",""))' 2>/dev/null || true)
config_is_lua=false
[[ -e $shell_path/hypr/hyprland.lua ]] && config_is_lua=true
case "$dialect" in
  lua)     $config_is_lua && ok "shell speaks the Lua dialect, like the configuration" \
             || warn "shell speaks Lua but the session started from hyprland.conf" ;;
  legacy)  $config_is_lua && fail "shell speaks the legacy dialect but the session runs hyprland.lua (settings will not reach the compositor)" \
             || ok "shell speaks the legacy dialect, like the configuration" ;;
  unknown) warn "shell has not worked out which Hyprland dialect to speak" ;;
  *)       warn "could not read the shell's Hyprland dialect" ;;
esac
# The running instance's log (quickshell.log starts fresh with every shell
# start; the previous one is quickshell.log.old).
log=$(quickshell log --path "$shell_path" 2>/dev/null)
log_file="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/quickshell.log"
[[ -z $log && -r $log_file ]] && log=$(tail -n 400 "$log_file")
if [[ -n $log ]]; then
  problems=$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$log" | grep -E 'ERROR|TypeError|ReferenceError|is not a type' | grep -vE 'desktopentry' | tail -3)
  [[ -z $problems ]] && ok "shell log has no errors" || warn "shell log: $problems"
  # The shell starts before the portal work on purpose (a slow portal used to
  # keep the screen black), so Qt's registration attempt can fail once. Only a
  # portal that stays unreachable is a problem.
  if grep -q 'Failed to register with host portal' <<<"$log"; then
    busctl --user status org.freedesktop.portal.Desktop >/dev/null 2>&1 \
      && ok "portal registration retried after the shell started" \
      || warn "the portal is not reachable (the shell could not register with it)"
  fi
fi
# Login timeline from scripts/session-init.sh: which step took the time when
# the screen stayed black longer than usual.
startup_log="${XDG_STATE_HOME:-$HOME/.local/state}/buchhwin-shell/startup.log"
if [[ -r $startup_log ]]; then
  slowest=$(sed -E 's/^[0-9:]+ \+ *([0-9]+)ms /\1 /' "$startup_log" | sort -rn | head -1)
  total=${slowest%% *}
  if (( ${total:-0} > 5000 )); then
    warn "login setup took ${total} ms; see $startup_log"
  else
    ok "login setup took ${total:-?} ms (shell start included)"
  fi
  printf '    %s\n' "$(tr '\n' '|' < "$startup_log" | sed 's/|/ | /g')" | cut -c1-400
else
  warn "no startup timeline yet (it is written at the next login)"
fi
layout_version=$(jq -r '.configVersion // empty' "$config_home/buchhwin-shell/layout.json" 2>/dev/null)
[[ $layout_version == 2 ]] && ok "layout.json uses format v2" || warn "layout.json not migrated yet (version '${layout_version:-missing}')"
owner=$(busctl --user status org.freedesktop.Notifications 2>/dev/null | sed -n 's/^Comm=//p')
[[ $owner == quickshell || $owner == .quickshell* ]] && ok "notifications are handled by the shell" || warn "notification service is owned by '${owner:-nobody}'"

section "Keyring and portals"
# `--auto-start=no`, because this script says of itself that it changes
# nothing: `org.freedesktop.portal.Desktop` is an activatable name, so a plain
# introspect *starts* the portal on a session where it is down. The same guard
# accounts-status.sh and kdeconnect-status.sh already use.
if busctl --user --auto-start=no introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop 2>/dev/null | grep -q 'org.freedesktop.portal.Secret'; then ok "Secret portal available (Brave sync through KWallet)"; else fail "Secret portal is missing or not running"; fi
# ksecretd is the one PAM unlocks; kwalletd6 is the legacy daemon nothing
# unlocks, so anything that woke it will be asking for a password by hand.
#
# Whether it is *unlocked* is asked, not assumed. This line used to say
# "unlocked by PAM at login" on the strength of the process being alive, which
# is a different fact - and a check that claims more than it measures is worse
# than no check, because the next person believes it.
if running ksecretd; then
  wallet_locked=$(busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/kdewallet \
    org.freedesktop.Secret.Collection Locked 2>/dev/null | awk '{print $2}')
  case "$wallet_locked" in
    false) ok "the secret service is unlocked (PAM handed it the login password)" ;;
    true)  warn "the secret service is running but locked: the next app that wants a secret will ask for a password" ;;
    *)     warn "the secret service is running; its lock state could not be read" ;;
  esac
else
  warn "the secret service is not running yet (starts on first access)"
fi
if running kwalletd6; then
  warn "kwalletd6 is also running: something asked for the legacy interface, which nothing unlocks"
fi
# Process names are cut to 15 characters (polkit-kde-authentication-agent-1).
running polkit-kde-auth && ok "PolicyKit agent is running" || fail "PolicyKit agent is missing"

section "Power and hardware"
if [[ $(setting '.power.lockBeforeSleep') != false ]]; then
  running swayidle 'before-sleep' && ok "lock before sleep is active" || fail "swayidle (lock before sleep) is not running"
fi
[[ -r /etc/pam.d/buchhwin-lock ]] && ok "lock screen PAM service installed" || fail "/etc/pam.d/buchhwin-lock is missing (sudo install/system-install.sh)"
# 0.55 answers "bool: true", 0.56 "int: 1".
lock_restore=$(hyprctl getoption misc:allow_session_lock_restore 2>/dev/null | head -1)
[[ $lock_restore == *1 || $lock_restore == *true ]] && ok "a crashed lock screen can be restarted" || warn "misc:allow_session_lock_restore is off"
command -v systemd-run >/dev/null 2>&1 && ok "lock screen launcher available" || fail "systemd-run is missing (lock falls back to swaylock)"
# Idle and lid settings exist per power source (power.battery / power.ac);
# files from before the split still have the single power.lidAction.
power_source=ac
if command -v upower >/dev/null 2>&1; then
  upower -d 2>/dev/null | grep -qE '^[[:space:]]*on-battery:[[:space:]]*yes' && power_source=battery
else
  online=0
  for supply in /sys/class/power_supply/*; do
    [[ $(cat "$supply/type" 2>/dev/null) != Battery && $(cat "$supply/online" 2>/dev/null) == 1 ]] && online=1
  done
  compgen -G '/sys/class/power_supply/BAT*' >/dev/null && [[ $online == 0 ]] && power_source=battery
fi
source_label=$([[ $power_source == battery ]] && echo "on battery" || echo "plugged in")
lid=$(setting ".power.$power_source.lidAction // .power.lidAction // \"suspend\"")
profile=$(setting ".power.$power_source.profile // \"keep\"")
ok "power source: $source_label (automatic profile: $profile)"
if [[ $lid != suspend ]]; then
  systemd-inhibit --list 2>/dev/null | grep -q buchhwin-shell && ok "lid ($source_label): $lid (logind inhibited)" || fail "lid setting '$lid' ($source_label) without a logind inhibitor"
else
  ok "lid ($source_label): sleep (system default)"
fi
running python3 'bluetooth-agent.py' && ok "Bluetooth pairing agent is running" || warn "Bluetooth pairing agent is not running (no adapter?)"
night=$(setting '.nightLight.mode // "off"')
if [[ $night == manual ]]; then pgrep -u "$(id -u)" -x gammastep >/dev/null && ok "Night Light is active" || fail "Night Light is on, but gammastep is not running"; else ok "Night Light: $night"; fi
[[ -n ${XCURSOR_THEME:-} ]] && ok "cursor $XCURSOR_THEME ${XCURSOR_SIZE:-}" || warn "XCURSOR_THEME is not set"

section "Tools"
if [[ $(setting '.clipboard.history') != false ]]; then
  running wl-paste "cliphist -db-path ${XDG_CACHE_HOME:-$HOME/.cache}/buchhwin-shell/cliphist.db" && ok "clipboard history is recording" || fail "clipboard history is not running"
fi
if [[ $(setting '.autostart.system') != false ]]; then
  systemctl --user is-active --quiet xdg-desktop-autostart.target && ok "standard autostart is active" || warn "xdg-desktop-autostart.target is not active"
  source "$project_dir/scripts/lib/autostart-skip.sh"
  for unit in $(autostart_skip_units); do
    [[ $(systemctl --user is-enabled "$unit" 2>/dev/null) == masked-runtime ]] || warn "autostart entry not skipped: $unit"
  done
fi
for tool in grim slurp wl-copy cliphist swappy gammastep curl; do
  command -v "$tool" >/dev/null 2>&1 || warn "$tool is missing"
done
if command -v wf-recorder >/dev/null 2>&1; then
  ok "screen recorder: wf-recorder"
elif command -v gpu-screen-recorder >/dev/null 2>&1; then
  ok "screen recorder: gpu-screen-recorder"
elif flatpak info com.dec05eba.gpu_screen_recorder >/dev/null 2>&1; then
  ok "screen recorder: gpu-screen-recorder (Flatpak)"
else
  warn "no screen recorder (sudo dnf install wf-recorder)"
fi

printf '\n'
if (( failures == 0 )); then
  printf 'Result: no errors, %d warning(s).\n' "$warnings"
else
  printf 'Result: %d error(s), %d warning(s).\n' "$failures" "$warnings"
fi
exit $(( failures > 0 ))
