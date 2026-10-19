#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
# `--reap [DIR]` only ends the helpers a dead shell of DIR left behind (see
# reap_helpers below) and starts nothing; the session launcher asks for it on
# the way out.
reap_only=0
if [[ ${1:-} == --reap ]]; then
  reap_only=1
  shift
fi
# The Hyprland config passes the exact path so IPC calls with the same --path
# reach this instance.
if [[ -n ${1:-} ]]; then
  config_dir=$1
elif [[ -e "$installed_dir/shell.qml" && $(readlink -f "$installed_dir") == "$project_dir" ]]; then
  config_dir="$installed_dir"
else
  config_dir=${BUCHHWIN_SHELL_PATH:-$project_dir}
fi
# The shell talks to Hyprland through HYPRLAND_INSTANCE_SIGNATURE, and it
# inherits that from whoever started it. Started from a terminal outside the
# session - which is what scripts/deploy.sh does - it would inherit nothing and
# come up blind: no monitors in Settings > Displays, no saved scaling applied,
# no window rules, no dispatches, and one warning in the log to say so. So the
# signature is resolved here when it is missing, and only when exactly one
# instance is running: a second one means a nested test session, and guessing
# between them is how a test reaches the real session.
#
# The one instance must also be the display this script was given: started
# from a Plasma terminal while a Hyprland runs on another seat or VT, its
# signature with KWin's WAYLAND_DISPLAY is a shell on KWin talking to that
# other compositor.
if (( ! reap_only )) && [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
  listed=$(hyprctl instances 2>/dev/null) || listed=""
  if [[ $(grep -c '^instance ' <<<"$listed") == 1 ]]; then
    listed_socket=$(sed -n 's/^[[:space:]]*wl socket: *//p' <<<"$listed" | head -n1) || listed_socket=""
    if [[ -n ${WAYLAND_DISPLAY:-} && -n $listed_socket && $listed_socket != "$WAYLAND_DISPLAY" ]]; then
      printf 'start-shell: the Hyprland instance runs on %s, this is %s; not adopting it\n' "$listed_socket" "$WAYLAND_DISPLAY" >&2
    else
      HYPRLAND_INSTANCE_SIGNATURE=$(sed -n 's/^instance \(.*\):$/\1/p' <<<"$listed" | head -n1) || HYPRLAND_INSTANCE_SIGNATURE=""
      if [[ -n $HYPRLAND_INSTANCE_SIGNATURE ]]; then export HYPRLAND_INSTANCE_SIGNATURE; fi
    fi
  else
    printf 'start-shell: no single Hyprland instance\n' >&2
  fi
fi

# ---- a nested session's shell is a nested session's ------------------------
# scripts/nested-session.sh starts its Hyprland with BUCHHWIN_NESTED=1 and the
# sandbox's XDG directories, and a shell that compositor starts has them. A
# shell restarted into it from a terminal (scripts/reload-shell.sh with the
# nested signature and display, as the testing recipe exports them) had only
# what the terminal had: it took the real ~/.config and ~/.local/state, moved
# the live shell's log aside, and with every BUCHHWIN_NESTED gate open it
# queued for the host's notification name, took the host's Bluetooth agent
# and ran the autostart apps (19.10.). The compositor says which session it
# is: its lock file beside the socket names its pid first, and that
# process's environment is the one to take - the same proof nested-guard.sh
# and nested-session.sh stop trust. A sandbox file left behind by a session
# that is gone cannot fool it, and the real session's Hyprland carries none
# of this, so nothing changes there.
nested_note=""
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  compositor_pid=$(sed -n 1p "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock" 2>/dev/null) || compositor_pid=""
  compositor_env=""
  if [[ $compositor_pid =~ ^[0-9]+$ ]]; then
    # Captured, then searched (pitfall 15).
    compositor_env=$({ tr '\0' '\n' <"/proc/$compositor_pid/environ"; } 2>/dev/null) || compositor_env=""
  fi
  if grep -qx 'BUCHHWIN_NESTED=1' <<<"$compositor_env"; then
    for name in BUCHHWIN_NESTED BUCHHWIN_NESTED_DIR BUCHHWIN_NESTED_MODE BUCHHWIN_NESTED_SCALE \
                XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
      value=""; found=0
      while IFS= read -r line; do
        if [[ $line == "$name="* ]]; then value=${line#*=}; found=1; break; fi
      done <<<"$compositor_env"
      (( found )) || continue
      if [[ ${!name-} != "$value" ]]; then
        nested_note+="${nested_note:+, }$name=$value (was ${!name-unset})"
        export "$name=$value"
      fi
    done
  fi
fi

state_dir=${XDG_STATE_HOME:-"$HOME/.local/state"}/buchhwin-shell
log_file="$state_dir/quickshell.log"
mkdir -p -- "$state_dir"

# ---- no Hyprland, no shell ---------------------------------------------------
# This is a Hyprland shell, and without a Hyprland to belong to it used to
# start anyway, "without one". Run from a Plasma session - a deploy or a
# reload from the desk where Citrix runs, an agent in an editor there - it
# came up on KWin's display: its bar, notch and wallpaper over the Plasma
# desktop, its notification server, clipboard watchers and lid inhibitor in
# that session, and before that it SIGKILLed Plasma's own kded6 for holding
# the tray name. So the shell starts only with a
# signature whose compositor socket is there: the session's own (Hyprland
# exports it to everything it starts, the login included) or the one
# instance resolved above. A signature without its socket is a session that
# is gone - one the user manager still remembers from the last Hyprland
# login hands it to a Plasma terminal. The socket is waited for briefly, so
# a start racing its compositor is not taken for that. A live one of a
# Hyprland on another VT comes the same way, next to KWin's display: the
# lock file Hyprland keeps beside its socket names its display (its pid,
# then its socket; `hyprctl instances` reads it), and another display than
# this one is no session here. Without that line nothing is said.
#
# BUCHHWIN_START_WITHOUT_HYPRLAND=1 is the tests' way past this: they run
# stand-in shells outside any session, and say so.
hyprland_socket() {
  printf '%s/hypr/%s/.socket.sock' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" "${HYPRLAND_INSTANCE_SIGNATURE:-}"
}
if (( ! reap_only )) && [[ ${BUCHHWIN_START_WITHOUT_HYPRLAND:-0} != 1 ]]; then
  session_found=0
  why=""
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    for _ in {1..20}; do
      if [[ -S $(hyprland_socket) ]]; then session_found=1; break; fi
      sleep 0.1
    done
  fi
  if (( session_found )) && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    lock_display=$(sed -n 2p "$(dirname -- "$(hyprland_socket)")/hyprland.lock" 2>/dev/null) || lock_display=""
    if [[ -n $lock_display && $lock_display != "$WAYLAND_DISPLAY" ]]; then
      session_found=0
      why="Hyprland $HYPRLAND_INSTANCE_SIGNATURE runs on $lock_display, this is $WAYLAND_DISPLAY"
    fi
  fi
  if (( ! session_found )); then
    if [[ -n $why ]]; then
      :
    elif [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
      why="Hyprland $HYPRLAND_INSTANCE_SIGNATURE has no socket any more"
    else
      why="no Hyprland session found"
    fi
    printf 'start-shell: %s; not starting the shell (it starts with the next Hyprland login)\n' "$why" >&2
    printf '%s start-shell: %s (WAYLAND_DISPLAY %s, XDG_CURRENT_DESKTOP %s); not starting the shell\n' \
      "$(date -Is)" "$why" "${WAYLAND_DISPLAY:-unset}" "${XDG_CURRENT_DESKTOP:-unset}" >>"$log_file"
    exit 1
  fi
fi

# Is an instance of this configuration listed? The answer is captured and then
# searched, never piped into `grep -q`: grep quits at its first match, the
# writer is left with SIGPIPE, and under pipefail that read as "no instance" -
# the restart below then stopped waiting for the dead instance to go, and the
# shell it started exited at once against it. The same mistake fc-list made in
# bootstrap.sh (docs/testing.md, Pitfalls).
instance_running() {
  local list
  list=$(quickshell list --path "$config_dir" --json 2>/dev/null) || return 1
  [[ $list == *'"id"'* ]]
}
# The session launcher asks for --reap with no WAYLAND_DISPLAY, and `quickshell
# list --path` only lists the instances on its own display: the wait below for
# a shell still on its way out never waited. `--all` lists every display's;
# the configuration is then told by its path. The JSON carries the path the
# shell was started with, a symlink or not, so both sides are resolved.
instance_listed_anywhere() {
  local list paths path want
  list=$(quickshell list --all --json 2>/dev/null) || return 1
  if ! command -v jq >/dev/null 2>&1; then
    [[ $list == *"\"$config_dir/shell.qml\""* || $list == *"\"$real_dir/shell.qml\""* ]]
    return
  fi
  want=$(readlink -f -- "$config_dir/shell.qml" 2>/dev/null) || want="$config_dir/shell.qml"
  paths=$(jq -r '.[]?.config_path // empty' <<<"$list" 2>/dev/null) || paths=""
  while IFS= read -r path; do
    [[ -n $path ]] || continue
    if [[ $path == "$config_dir/shell.qml" || $(readlink -f -- "$path" 2>/dev/null) == "$want" ]]; then
      return 0
    fi
  done <<<"$paths"
  return 1
}
note() { printf '%s start-shell: %s\n' "$(date -Is)" "$1" >>"$log_file"; }

# ---- the helpers a dead shell leaves behind ---------------------------------
# Quickshell's `Process` children are ordinary child processes, and a shell
# that dies on a signal - a crash, or the abort on losing the compositor at
# logout - runs no destructor that would end them. `nmcli monitor`, `udevadm
# monitor`, the lid inhibitor, cliphist's two wl-paste watchers, the drive
# watchers (udisksctl monitor, gio mount -o) and the bluetooth agent then live
# on under PID 1: three of them from the
# previous login were still running on 2026-10-13, and a shell restarted after
# a crash starts a second set beside them (two wl-paste watchers storing into
# the same database). So they are ended before a replacement starts, and once
# more when the session ends (`--reap`, from the session launcher).
#
# Only this user's processes (`-u`), only whole command lines (anchored, the
# paths escaped), and only real orphans: a helper whose parent is PID 1, or
# the user manager that adopts what is orphaned below it (a shell restarted
# by the shell update's service). A living quickshell's helpers are its own -
# a nested test session runs beside the real one with helpers that look the
# same - and "any parent but a quickshell" also took the user's own `nmcli
# monitor` in a terminal (parent zsh) on every reload and deploy (16.10.).
#
# pgrep -f takes a regular expression; the path is a literal, so every
# character that means something to an ERE is escaped first (reload-shell.sh
# does the same). Quickshell may hand its scripts the resolved path rather
# than the symlink it was started through, so both spellings are accepted.
# The executable itself is listed by name or by its resolved path, and the
# python scripts run through their interpreter (`python3 <script> …`).
escape_ere() { printf '%s' "$1" | sed 's,[][\.*^$+?(){}|\\],\\&,g'; }
config_pattern=$(escape_ere "$config_dir")
real_dir=$(readlink -f -- "$config_dir" 2>/dev/null || printf '%s' "$config_dir")
if [[ $real_dir != "$config_dir" ]]; then
  config_pattern="($config_pattern|$(escape_ere "$real_dir"))"
fi
helper_patterns=(
  "^(\\S+ )?${config_pattern}/scripts/drives\\.py monitor\$"
  '^(\S*/)?udisksctl monitor$'
  '^(\S*/)?gio mount -o$'
  "^(\\S+ )?${config_pattern}/scripts/bluetooth-agent\\.py\$"
  '^(\S*/)?wl-paste --type (text|image) --watch cliphist -db-path \S*/buchhwin-shell/cliphist\.db -max-items [0-9]+ store$'
  '^(\S*/)?nmcli monitor$'
  '^(\S*/)?udevadm monitor --udev --subsystem-match=backlight$'
  '^(\S*/)?systemd-inhibit --what=handle-lid-switch --who=buchhwin-shell .* sleep infinity$'
)
orphan_parent() {
  [[ $1 == 1 ]] && return 0
  [[ $(cat "/proc/$1/comm" 2>/dev/null || true) == systemd ]]
}
reap_helpers() {
  local uid pattern pid parent parents reaped=0
  uid=$(id -u)
  for pattern in "${helper_patterns[@]}"; do
    parents=
    for pid in $(pgrep -u "$uid" -f "$pattern" 2>/dev/null || true); do
      parent=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null || true)
      [[ -n $parent ]] || continue
      orphan_parent "$parent" || continue
      [[ ,$parents, == *,"$parent",* ]] || parents+=${parents:+,}$parent
      reaped=$(( reaped + 1 ))
    done
    [[ -n $parents ]] || continue
    # By parent rather than by pid: the parent was just checked, and the
    # pattern keeps it to the helpers.
    pkill -u "$uid" -P "$parents" -f "$pattern" 2>/dev/null || true
  done
  if (( reaped )); then note "ended $reaped helper(s) left behind by a shell that is gone"; fi
}

if (( reap_only )); then
  # Called as the compositor ends, with the shell on its way out behind it
  # (losing the compositor is an abort, not an exit): wait for its instance
  # to go, up to 5 s, rather than end helpers it still owns, and leave them
  # alone if it never goes.
  for _ in {1..100}; do
    instance_listed_anywhere || break
    sleep 0.05
  done
  if instance_listed_anywhere; then
    note "asked to reap, but an instance of this configuration is still listed - leaving its helpers alone"
  else
    reap_helpers
  fi
  exit 0
fi

# Every other way out ends what the shell left behind too: a SIGTERM that the
# shell dies of, a status that is not a crash, the compositor gone (how every
# nested test session ends) and the restart limit. Only once the instance is
# no longer listed, as above; helpers now carry --pdeathsig (Paths.bound),
# this is the net for anything that does not. And it waits for the sweep of
# the instance directories below (a few seconds at most), so nothing this
# script started outlives it.
trap 'instance_running || reap_helpers; if [[ -n ${sweep_pid:-} ]]; then wait "$sweep_pid" 2>/dev/null || true; fi' EXIT

# One log per shell start; the previous one is kept as quickshell.log.old. A
# start that finds a running instance (--no-duplicate exits at once) keeps the
# log, because that instance still writes to it.
if ! instance_running; then
  [[ -e $log_file ]] && mv -f -- "$log_file" "$log_file.old"
fi
# In the log of the shell it concerns, so after the move.
if [[ -n $nested_note ]]; then note "the compositor is a nested session; taken from it: $nested_note"; fi

# Quickshell leaves an instance directory in the runtime directory (tmpfs)
# for every shell, test and nested run, and nothing else removes them; those
# of instances that are gone go with this start
# (scripts/lib/quickshell-dirs.sh: unlocked and unchanged for an hour). In
# the background, beside the first shell this script starts, and once that
# shell is listed (or gone): the sweep costs ~4 ms a directory, the first one
# of a runtime directory with a thousand took four seconds, and a start that
# waited for it was not up when a nested smoke test asked for it - while
# reload-shell.sh, after four seconds without an instance, starts a second
# one. Waiting for the listing keeps the sweep from taking the empty by-shell
# directory this shell is about to link itself into.
# shellcheck source=lib/quickshell-dirs.sh
if [[ -r "$project_dir/scripts/lib/quickshell-dirs.sh" ]]; then
  source "$project_dir/scripts/lib/quickshell-dirs.sh"
fi
sweep_pid=
start_sweep() {
  [[ -z $sweep_pid ]] && declare -F quickshell_sweep_dirs >/dev/null || return 0
  (
    for _ in {1..100}; do
      if ! kill -0 "$1" 2>/dev/null || instance_running; then break; fi
      sleep 0.1
    done
    quickshell_sweep_dirs 60
  ) </dev/null >/dev/null 2>&1 &
  sweep_pid=$!
}

# ---- and it is watched while it runs ---------------------------------------
# The shell used to be `exec`ed and that was the end of this script's job, so a
# crash simply left the desktop without a shell until somebody noticed. It is
# not hypothetical: `coredumpctl` on 2026-09-22 listed **six** SIGSEGVs of
# quickshell in one day, all of them inside Qt's own HTTP/2 header parser
# (`QHttpHeaderParser::setStatusCode` under `QHttp2ProtocolHandler`, reached
# through OpenSSL) - not this project's QML, and nothing this project can fix.
# What it can do is come back.
#
# **Only a crash is restarted.** `stop-shell.sh` and `deploy.sh` end the shell
# with `quickshell kill`, which is a clean exit, and a SIGTERM is somebody
# asking it to go; either would otherwise race the caller by starting a second
# shell behind it. A process that died on a signal reports 128 + that signal,
# so the two cases are told apart exactly rather than guessed at.
#
# **And only five times a minute**, the same brake systemd would have applied:
# a shell that crashes on startup must not spin for ever. Past that it stops
# and says so, in the log the next person will read anyway.
#
# **And never into a session that is ending.** At logout and at shutdown
# systemd sends SIGTERM to everything in the session at once, and a shell
# that dies badly on the way out - Quickshell does, its IPC and reload paths
# both segfault - looked like a crash to be restarted: a fresh shell started
# against a compositor that was already gone, and blocked on its socket until
# systemd gave up on it 90 seconds later, with the user watching the spinner
# ("since yesterday I cannot restart any more"). So the SIGTERM this script
# receives is forwarded to the shell and ends the watching, and a restart is
# only ever attempted while the compositor's socket is still there.
restart_window=60
restart_limit=5
restarts=0
window_started=$SECONDS
stopping=0
child=

# Without a signature there is nothing to check against (only a test's start
# gets this far without one, BUCHHWIN_START_WITHOUT_HYPRLAND), and the answer
# is the one this script always gave.
compositor_alive() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
  [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]
}
on_stop() {
  stopping=1
  [[ -n $child ]] && kill -TERM "$child" 2>/dev/null || true
}
trap on_stop TERM INT HUP

# A caller that itself came from a shell - a terminal or an editor the shell
# started, running a reload or a deploy - carries that shell's own settings
# below. They are undone first (scripts/lib/app-env.sh), so the shell starts
# from the session's values and its record of them stays right. This is the
# session's start: a missing or broken file costs the undoing, not the shell.
app_env="$project_dir/scripts/lib/app-env.sh"
# shellcheck source=lib/app-env.sh
if [[ -r $app_env ]] && source "$app_env" && declare -F app_env_restore >/dev/null; then
  app_env_restore || true
fi

# The session exports QT_QPA_PLATFORMTHEME=kde for the applications; the shell
# itself runs without it (2026-10-13). The KDE platform theme plugin pulled
# KConfig, KIconThemes and KColorScheme into quickshell and watched kdeglobals
# for 35 MB of resident memory (377 → 343 MB in a nested session), and the
# shell used none of it: its fonts and colours are its own tokens, its dialogs
# are kdialog, and the one thing it did take from the plugin - the icon theme's
# name for Quickshell.iconPath - is handed over here through QS_ICON_THEME,
# read from kdeglobals like the plugin did, else chosen by what the shell's
# panels are (the symbolic icons of a dark theme are light). Launcher
# screenshots with and without the plugin differ in 604 of 537 600 pixels.
icon_theme=""
# Set when the panels chose, so the shell can tell when they have changed
# under it (services/SessionService.qml): Qt reads the icon theme once, at
# the start.
icon_theme_auto=""
kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
# Guarded and status-caught: under `set -e` with pipefail a missing file (a
# nested session's sandbox has none) would end this script here, before the
# shell ever started (pitfall 15).
if [[ -r $kdeglobals ]]; then
  icon_theme=$(sed -n '/^\[Icons\]/,/^\[/{s/^Theme=//p}' "$kdeglobals" 2>/dev/null | head -n1) || icon_theme=""
fi
# The panels decide, as theme/Colors.qml's surfaceDark does: a panel colour
# chosen in Settings > Appearance is what it is (dark below the luminance of
# PanelStyleLogic.isLight, 0.179; three or six hex digits, with or without
# the #), and the theme's own panels follow the theme, "auto" being dark
# from 19:00 to 07:00. The theme alone decided before: "auto" always got the
# dark theme's light icons, by day on light cards too, and the buchhwin
# profile's black panels in the light theme got dark icons on black.
panels_light='
  def channel: if . <= 0.04045 then . / 12.92 else pow((. + 0.055) / 1.055; 2.4) end;
  def digit: if . >= 97 then . - 87 else . - 48 end;
  def byte: explode | map(digit) | .[0] * 16 + .[1];
  (.appearance.panelColor // "auto") as $stored
  | (if ($stored | type) == "string" then $stored | gsub("^\\s+|\\s+$"; "") | ltrimstr("#") | ascii_downcase else "" end) as $hex
  | (if ($hex | test("^[0-9a-f]{3}$")) then ($hex | split("") | map(. + .) | join("")) else $hex end) as $hex
  | if ($hex | test("^[0-9a-f]{6}$")) then
      [$hex[0:2], $hex[2:4], $hex[4:6]] | map(byte / 255 | channel)
      | (0.2126 * .[0] + 0.7152 * .[1] + 0.0722 * .[2]) > 0.179
    else
      (.appearance.theme // "dark") as $theme
      | ($theme == "dark" or ($theme == "auto" and ($hour >= 19 or $hour < 7))) | not
    end'
if [[ -z $icon_theme ]]; then
  icon_theme=breeze-dark
  icon_theme_auto=1
  settings="${XDG_CONFIG_HOME:-$HOME/.config}/buchhwin-shell/settings.json"
  if command -v jq >/dev/null 2>&1 && [[ -s $settings ]] \
     && [[ $(jq -r --argjson hour "$(( 10#$(date +%H) ))" "$panels_light" "$settings" 2>/dev/null) == true ]]; then
    icon_theme=breeze
  fi
fi

# The allocator gives every thread that allocates an arena of its own. The
# shell runs dozens of threads - a render thread per mapped window and Mesa's
# workers per GL context - and two arenas are plenty for a program whose work
# happens on the GUI thread. Which knob that takes depends on how quickshell
# was built:
# - glibc's malloc (up to 8 arenas per core) reads MALLOC_ARENA_MAX. On Leap
#   on 2026-10-13 about 410 of the shell's 770 MB sat in 94 such arenas,
#   mostly fragmented free space.
# - jemalloc, which Arch's quickshell links (libjemalloc.so.2 is its first
#   NEEDED library; its malloc and new then serve the whole process), never
#   reads MALLOC_ARENA_MAX and runs with its defaults: 48 arenas on 12 CPUs, a
#   thread cache each, dirty pages kept 10 s. It reads MALLOC_CONF: two arenas,
#   a background thread that returns freed pages, and a one-second decay took
#   13-15 MB off the shell at start and 8-17 MB after panels were opened and
#   closed (nested, medians of three runs, 19.10.), at the same CPU per panel.
# Each is ignored by the other allocator, so both are set. An exported value
# wins (A/B).
malloc_arenas=${MALLOC_ARENA_MAX:-2}
malloc_conf=${MALLOC_CONF:-narenas:2,background_thread:true,dirty_decay_ms:1000}
# Mesa gives every GL context a marshalling thread (glthread) and a driver
# thread (Gallium's threaded context), for applications that are limited by
# GL calls on one thread. The shell draws a handful of light scene graphs,
# one context per mapped window: in a nested session (two outputs) that was
# 36 of its 94 threads and ~30 MB, for no frame it drew faster (14.10.,
# measured nested and live). The shell only; applications keep both. An
# exported value wins (A/B).
mesa_glthread_value=${mesa_glthread:-false}
gallium_thread=${GALLIUM_THREAD:-0}
# Qt's Wayland client gives every window a second EGL context, for the
# client-side decorations it draws around a toplevel - and the shell's
# windows are layer surfaces, which never have any (there is no
# FloatingWindow in the shell). Each such context held ~1.3 MB of Mesa's heap
# and a Mesa thread for the life of its window: off, the shell started 14 MB
# lighter nested (11 windows, medians of three runs, 19.10.), and one thread
# per window fewer. The shell only; applications keep their decorations.
disable_decorations=${QT_WAYLAND_DISABLE_WINDOWDECORATION:-1}
# Text drawn by Qt Quick's distance fields (Typography's QtRendering) is
# antialiased per subpixel by default on desktop GL: blue and orange fringes
# on the bar's and the taskbar's light text on black, an RGB order that is
# wrong on a rotated screen, and a subpixel blend that is wrong on
# translucent pills anyway. Greyscale is what the shell already showed where
# text went through a layer (the collapsed notch clock).
text_antialiasing=${QSG_DISTANCEFIELD_ANTIALIASING:-gray}
# All of the above is the shell's alone, and quickshell's environment is what
# every process it starts inherits: applications opened from the launcher
# ran with two arenas, without Mesa's threads and without the Plasma look.
# What this script changes is written down for scripts/launch-app.sh, which
# undoes it before it runs an application: the settings set here that the
# session did not have, and the platform theme the shell goes without. An
# exported value is the session's, and stays.
app_unset=()
for name in MALLOC_ARENA_MAX MALLOC_CONF mesa_glthread GALLIUM_THREAD QT_WAYLAND_DISABLE_WINDOWDECORATION \
            QSG_DISTANCEFIELD_ANTIALIASING QS_ICON_THEME BUCHHWIN_ICON_THEME_AUTO; do
  [[ -n ${!name:-} ]] || app_unset+=("$name")
done
app_qpa_theme=${QT_QPA_PLATFORMTHEME:-}
# Transparent huge pages: with the kernel set to `always` (Arch's default)
# the shell's heaps sit in mostly empty 2 MB pages - on 15.10. RssAnon was
# 340-349 MB with them and 178-182 MB without (nested, the screen the same).
# That is a setting of the machine, `madvise` on most desktops, and doctor.sh
# says so; it is not switched off from here any more. A prctl in front of
# quickshell did it for one day and every application the shell started -
# a browser from the launcher, a remote-desktop client from that browser -
# inherited it.

# The tray is the shell's: it is org.kde.StatusNotifierWatcher in this
# session. A kded6 that something D-Bus-activated (all 29 Plasma modules,
# statusnotifierwatcher among them) takes that name the moment a restarting
# shell lets go, and the tray stays empty (testing.md pitfalls 43 and 68).
# Unloading its module answers true and keeps the name; a SIGTERM makes it
# crash in its Wayland teardown and KCrash starts it again at once. So a
# kded6 found holding the name is ended with SIGKILL, which KCrash does not
# see - only that process, checked by its name, and never from a nested test
# session, whose shell must not touch the real one's bus. Only inside a live
# Hyprland session either: in a Plasma session the kded6 holding the name is
# Plasma's own (the tray watcher, the network agent, every kded module), and
# a test's start without Hyprland (BUCHHWIN_START_WITHOUT_HYPRLAND) is no
# session at all.
release_tray() {
  [[ ${BUCHHWIN_NESTED:-0} == 1 ]] && return 0
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -S $(hyprland_socket) ]] || return 0
  command -v busctl >/dev/null 2>&1 || return 0
  local listed pid
  listed=$(busctl --user --auto-start=no list --no-pager 2>/dev/null) || return 0
  pid=$(awk '$1 == "org.kde.StatusNotifierWatcher" && $3 == "kded6" { print $2 }' <<<"$listed")
  [[ $pid =~ ^[0-9]+$ ]] || return 0
  [[ $(cat "/proc/$pid/comm" 2>/dev/null) == kded6 ]] || return 0
  kill -KILL "$pid" 2>/dev/null || return 0
  note "ended kded6 (pid $pid): it held the tray's StatusNotifierWatcher name"
}

while true; do
  status=0
  release_tray
  env -u QT_QPA_PLATFORMTHEME QS_ICON_THEME="$icon_theme" BUCHHWIN_ICON_THEME_AUTO="$icon_theme_auto" \
    MALLOC_ARENA_MAX="$malloc_arenas" MALLOC_CONF="$malloc_conf" \
    mesa_glthread="$mesa_glthread_value" GALLIUM_THREAD="$gallium_thread" \
    QT_WAYLAND_DISABLE_WINDOWDECORATION="$disable_decorations" QSG_DISTANCEFIELD_ANTIALIASING="$text_antialiasing" \
    BUCHHWIN_APP_ENV_UNSET="${app_unset[*]}" BUCHHWIN_APP_QPA_THEME="$app_qpa_theme" \
    quickshell --no-duplicate --path "$config_dir" >>"$log_file" 2>&1 &
  child=$!
  start_sweep "$child"
  # `wait` returns as soon as a trapped signal arrives, before the shell has
  # gone; wait again for its real status.
  wait "$child" || status=$?
  while kill -0 "$child" 2>/dev/null; do
    status=0
    wait "$child" || status=$?
  done
  child=
  if (( stopping )); then
    note "asked to stop; the shell ended with status $status"
    exit 0
  fi
  (( status >= 128 )) || exit "$status"
  signal=$(( status - 128 ))
  # SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE. Anything else that carries a
  # signal - SIGTERM above all - is a request, not a fault.
  case $signal in
    11|6|7|4|8) ;;
    *) exit "$status" ;;
  esac
  if ! compositor_alive; then
    note "the shell died on signal $signal, but the compositor is gone - not restarting it"
    exit "$status"
  fi

  if (( SECONDS - window_started > restart_window )); then
    restarts=0
    window_started=$SECONDS
  fi
  restarts=$(( restarts + 1 ))
  if (( restarts > restart_limit )); then
    note "the shell died on signal $signal and has now done so $restart_limit times in ${restart_window}s - not restarting it again"
    exit "$status"
  fi
  note "the shell died on signal $signal, restarting ($restarts of $restart_limit)"
  sleep 1
  # The dead shell's instance can outlive it for a moment (the same lag
  # reload-shell.sh waits out): a replacement started against it exits 0 at
  # once because of --no-duplicate, and that 0 is read above as a clean exit -
  # the crash is then logged as restarted and the desktop has no shell. Wait
  # (up to 10 s) until quickshell no longer lists the instance.
  for _ in {1..200}; do
    instance_running || break
    sleep 0.05
  done
  # A SIGTERM during that pause found no shell to forward to (`child` is
  # empty) and only set `stopping`: the session is ending, and a shell started
  # now would start into it. The same for a compositor that went meanwhile.
  # The EXIT trap still ends the dead shell's helpers.
  if (( stopping )); then
    note "asked to stop while waiting to restart the shell - not restarting it"
    exit 0
  fi
  if ! compositor_alive; then
    note "the compositor went away while waiting to restart the shell - not restarting it"
    exit "$status"
  fi
  # Its helpers outlived it (reap_helpers above): ended now, before the
  # replacement starts its own, or two of each run side by side. Not while
  # the instance is still listed - then the helpers may still be its.
  if ! instance_running; then reap_helpers; fi
done
