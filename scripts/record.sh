#!/usr/bin/env bash
set -euo pipefail

# Screen recording for buchhwin-shell (services/RecordingService.qml). The
# shell builds the recorder command (services/recording/RecordingLogic.js);
# this script collects runtime facts and keeps the recorder alive in a
# detached supervisor, so a shell restart does not end a recording.
#   record.sh probe region|screen|window|none
#       JSON: installed recorders, and for a mode the selected region (slurp),
#       active window or focused output plus the default audio devices
#   record.sh start --file F --mode M --backend B [--audio A] [--notify] -- RECORDER ARGV…
#   record.sh stop      SIGINT to the recorder, waits until the file is written
#   record.sh status    state JSON ({"active":false} when idle; clears stale state)
# Global option: --state PATH (default $XDG_RUNTIME_DIR/buchhwin-shell/recording.json).
# --notify sends "Recording saved" / "Recording failed" with Open and Show in
# folder actions (only the real session passes it).

runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
state_file="$runtime_dir/buchhwin-shell/recording.json"
if [[ ${1:-} == --state ]]; then
  [[ -n ${2:-} ]] || { printf 'record.sh: --state needs a path\n' >&2; exit 2; }
  state_file=$2
  shift 2
fi
log_file="${state_file%.json}.log"

usage() {
  printf 'Usage: %s [--state PATH] {probe MODE|start --file F --mode M --backend B [--audio A] [--notify] -- ARGV…|stop|status}\n' "$0" >&2
  exit 2
}

alive() {
  [[ $1 =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

# Prints the state when a recording is running; removes a stale file.
current_state() {
  [[ -s $state_file ]] || return 1
  local supervisor
  supervisor=$(jq -r '.supervisor // 0' "$state_file" 2>/dev/null || printf 0)
  if alive "$supervisor"; then
    cat -- "$state_file"
    return 0
  fi
  rm -f -- "$state_file"
  return 1
}

probe() {
  local mode=${1:-none} wf=false gsr=false gsr_flatpak=false
  command -v wf-recorder >/dev/null 2>&1 && wf=true
  command -v gpu-screen-recorder >/dev/null 2>&1 && gsr=true
  if command -v flatpak >/dev/null 2>&1 && flatpak info com.dec05eba.gpu_screen_recorder >/dev/null 2>&1; then
    gsr_flatpak=true
  fi
  local geometry="" output="" sink="" source="" cancelled=false
  # Without a recorder there is nothing to select.
  if [[ $mode != none && ( $wf == true || $gsr == true || $gsr_flatpak == true ) ]]; then
    case "$mode" in
      region)
        geometry=$(slurp -d -b '#00000066' -c '#f07171' -w 2) || { geometry=""; cancelled=true; }
        ;;
      window)
        geometry=$(hyprctl -j activewindow | jq -r 'if .at then "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])" else empty end' || true)
        ;;
      screen)
        output=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name' | head -n 1 || true)
        ;;
      *) usage ;;
    esac
    sink=$(pactl get-default-sink 2>/dev/null || true)
    source=$(pactl get-default-source 2>/dev/null || true)
  fi
  jq -cn --argjson wf "$wf" --argjson gsr "$gsr" --argjson gsrFlatpak "$gsr_flatpak" \
    --arg geometry "$geometry" --arg output "$output" --arg sink "$sink" --arg source "$source" \
    --argjson cancelled "$cancelled" \
    '{backends: {wfRecorder: $wf, gsr: $gsr, gsrFlatpak: $gsrFlatpak}, cancelled: $cancelled,
      geometry: $geometry, output: $output, sink: $sink, source: $source}'
}

start() {
  local file="" mode="" backend="" audio=off notify=0
  while (($#)); do
    case "$1" in
      --file) file=${2:-}; shift 2 ;;
      --mode) mode=${2:-}; shift 2 ;;
      --backend) backend=${2:-}; shift 2 ;;
      --audio) audio=${2:-off}; shift 2 ;;
      --notify) notify=1; shift ;;
      --) shift; break ;;
      *) usage ;;
    esac
  done
  [[ -n $file && -n $mode && $# -gt 0 ]] || usage
  if current_state >/dev/null; then
    printf 'failed A recording is already running\n'
    exit 3
  fi
  mkdir -p -- "$(dirname -- "$file")" "$(dirname -- "$state_file")"
  rm -f -- "$state_file"
  setsid "$0" --state "$state_file" _supervise "$file" "$mode" "$backend" "$audio" "$notify" "$@" \
    </dev/null >"$log_file" 2>&1 &
  # The supervisor writes the state as soon as the recorder runs; a recorder
  # that fails at once (no permission, unsupported output) ends within a moment.
  local i
  for i in {1..30}; do
    [[ -s $state_file ]] && break
    sleep 0.1
  done
  sleep 0.5
  if current_state; then
    return 0
  fi
  printf 'failed %s\n' "$(tail -n 1 -- "$log_file" 2>/dev/null | tr -d '\r' || true)"
  exit 1
}

# All processes below PID (flatpak run → bwrap → recorder).
descendants() {
  local children child
  children=$(ps -o pid= --ppid "$1" 2>/dev/null || true)
  for child in $children; do
    printf '%s\n' "$child"
    descendants "$child"
  done
}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send "$@" 2>/dev/null || true
}

supervise() {
  local file=$1 mode=$2 backend=$3 audio=$4 notify_enabled=$5
  shift 5
  "$@" &
  local pid=$!
  local started
  started=$(date +%s%3N)
  jq -cn --argjson pid "$pid" --argjson supervisor "$$" --arg file "$file" --arg mode "$mode" \
    --arg backend "$backend" --arg audio "$audio" --argjson started "$started" \
    '{active: true, pid: $pid, supervisor: $supervisor, file: $file, mode: $mode, backend: $backend,
      audio: $audio, started: $started}' > "$state_file.tmp"
  mv -f -- "$state_file.tmp" "$state_file"
  # A terminated supervisor still lets the recorder finish its file.
  trap 'kill -INT "$pid" 2>/dev/null || true' TERM
  local status=0
  while alive "$pid"; do
    wait "$pid" || status=$?
  done
  rm -f -- "$state_file"
  local seconds=$(( ($(date +%s%3N) - started) / 1000 ))
  local duration
  duration=$(printf '%d:%02d' $((seconds / 60)) $((seconds % 60)))
  if [[ -s $file ]]; then
    printf 'saved %s (%s, exit %s)\n' "$file" "$duration" "$status"
    [[ $notify_enabled == 1 ]] || return 0
    local action
    action=$(notify-send --app-name="Screen recording" --icon=media-record \
      --action=open=Open --action=folder="Show in folder" \
      "Recording saved" "${file##*/} · $duration" 2>/dev/null || true)
    case "$action" in
      open) xdg-open "$file" >/dev/null 2>&1 & ;;
      folder)
        local uri
        uri=$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$file")
        # The URI is an argument, not text inside a GVariant literal: a quote
        # or bracket in the file name broke the literal and the call.
        busctl --user --timeout=5 call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 \
          org.freedesktop.FileManager1 ShowItems ass 1 "$uri" "" >/dev/null 2>&1 \
          || xdg-open "${file%/*}" >/dev/null 2>&1 &
        ;;
    esac
  else
    rm -f -- "$file"
    printf 'recorder exited with %s without writing %s\n' "$status" "$file"
    [[ $notify_enabled == 1 ]] && notify --app-name="Screen recording" --icon=media-record \
      "Recording failed" "${backend:-The recorder} stopped without saving a video. Details: $log_file"
  fi
  return 0
}

stop() {
  local state
  if ! state=$(current_state); then
    printf 'failed No recording is running\n'
    exit 1
  fi
  local pid file supervisor
  pid=$(jq -r '.pid' <<<"$state")
  supervisor=$(jq -r '.supervisor' <<<"$state")
  file=$(jq -r '.file' <<<"$state")
  # SIGINT lets the recorder finish the file. Flatpak runs the recorder inside
  # bwrap, so the signal goes to the recorder processes below the pid too.
  local targets=() candidate name
  for candidate in $(descendants "$pid"); do
    name=$(cat "/proc/$candidate/comm" 2>/dev/null || true)
    [[ $name == wf-recorder || $name == gpu-screen-reco* ]] && targets+=("$candidate")
  done
  ((${#targets[@]})) || targets=("$pid")
  kill -INT "${targets[@]}" 2>/dev/null || true
  local i
  # The supervisor removes the state once the recorder has exited (it may then
  # keep waiting for a click on the notification).
  for i in {1..150}; do
    [[ -e $state_file ]] && alive "$supervisor" || break
    sleep 0.1
  done
  if [[ -e $state_file ]] && alive "$supervisor"; then
    printf 'failed Still writing %s\n' "${file##*/}"
    exit 1
  fi
  if [[ -s $file ]]; then
    printf 'saved %s\n' "$file"
  else
    printf 'failed The recorder did not write a video (see %s)\n' "$log_file"
    exit 1
  fi
}

command=${1:-}
[[ -n $command ]] || usage
shift
case "$command" in
  probe) probe "$@" ;;
  start) start "$@" ;;
  stop) stop ;;
  status) current_state || printf '{"active":false}\n' ;;
  _supervise) supervise "$@" ;;
  *) usage ;;
esac
