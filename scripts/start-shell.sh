#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installed_dir="$HOME/.local/share/buchhwin-shell"
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
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
  if [[ $(hyprctl instances 2>/dev/null | grep -c '^instance ') == 1 ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances 2>/dev/null | sed -n 's/^instance \(.*\):$/\1/p' | head -1)
    export HYPRLAND_INSTANCE_SIGNATURE
  else
    printf 'start-shell: no single Hyprland instance; the shell starts without one\n' >&2
  fi
fi

state_dir=${XDG_STATE_HOME:-"$HOME/.local/state"}/buchhwin-shell
log_file="$state_dir/quickshell.log"
mkdir -p -- "$state_dir"

# One log per shell start; the previous one is kept as quickshell.log.old. A
# start that finds a running instance (--no-duplicate exits at once) keeps the
# log, because that instance still writes to it.
if ! quickshell list --path "$config_dir" --json 2>/dev/null | grep -q '"id"'; then
  [[ -e $log_file ]] && mv -f -- "$log_file" "$log_file.old"
fi

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

note() { printf '%s start-shell: %s\n' "$(date -Is)" "$1" >>"$log_file"; }
instance_running() { quickshell list --path "$config_dir" --json 2>/dev/null | grep -q '"id"'; }
# Without a signature there is nothing to check against (a test, or a start
# outside any session), and the answer is the one this script always gave.
compositor_alive() {
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || return 0
  [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]
}
on_stop() {
  stopping=1
  [[ -n $child ]] && kill -TERM "$child" 2>/dev/null || true
}
trap on_stop TERM INT HUP

while true; do
  status=0
  quickshell --no-duplicate --path "$config_dir" >>"$log_file" 2>&1 &
  child=$!
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
done
