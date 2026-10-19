#!/usr/bin/env bash
set -euo pipefail

# A command in the session's terminal (Settings > Default apps):
#
#   launch-terminal.sh [--hold] [--unit NAME] [--title TITLE] [--] [COMMAND [ARGS...]]
#
# The shell's own terminals (Settings > Updates, the cursor install) and the
# launcher's Terminal=true entries (htop, btop …) open here, in whichever
# terminal the session uses: they were kitty whatever Default apps said, and
# the launcher's ran with no terminal at all. Each terminal has its own words
# for the same three things - the command, a window title, and keeping the
# window open once the command has ended (--hold) - and one without a word for
# holding gets a wrapper that waits for Enter. Without a command the terminal
# opens a shell, and --hold means nothing.
#
# The terminal stays in the foreground. Konsole without --nofork, GNOME
# Terminal without --wait and WezTerm without --always-new-process hand the
# window to a process that is already running and return at once; the unit
# Settings > Updates watches (--unit) would then end with pacman still on
# screen. Alacritty does that too, on purpose, for everything but --unit
# (its daemon, scripts/launch-alacritty.sh): nothing else here waits for the
# window. Everything starts through scripts/launch-app.sh - kitty and
# Alacritty through their own launchers, which end there - so the terminal
# gets the session's environment rather than the shell's own settings
# (scripts/lib/app-env.sh), and a scope named after its entry or, with
# --unit, a user service of that name.
#
# Nothing set, or the chosen terminal not installed: kitty, which the session
# ships with.
# The path as it was called, resolved only when this file itself is a link
# (as in launch-default.sh): two processes and two subshells less per start.
self=${BASH_SOURCE[0]}
[[ $self == /* && ! -L $self ]] || self=$(readlink -f -- "$self")
project_dir=${self%/*/*}
usage='usage: launch-terminal.sh [--hold] [--unit NAME] [--title TITLE] [--] [COMMAND [ARGS...]]'

hold=false
unit=""
title=""
while (( $# )); do
  case $1 in
    --hold) hold=true; shift ;;
    --unit | --title)
      if (( $# < 2 )) || [[ -z $2 ]]; then
        printf 'launch-terminal: %s needs a value\n%s\n' "$1" "$usage" >&2
        exit 2
      fi
      if [[ $1 == --unit ]]; then unit=$2; else title=$2; fi
      shift 2 ;;
    --) shift; break ;;
    -*) printf 'launch-terminal: unknown option %s\n%s\n' "$1" "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
if (( $# == 0 )); then hold=false; fi

# The hold for terminals without one: the command, its exit status, and the
# window waits for Enter. POSIX sh, so it runs wherever the terminal starts
# it; the arguments are the command's, never part of the script.
hold_script='"$@"; status=$?; printf "\n[exit status %s] Press Enter to close this window." "$status"; read -r answer || :; exit "$status"'

# The program behind a desktop entry: the first word of its Exec= line in the
# first data directory that has it (the XDG order default-apps.py looks it up
# in), past an `env` and its VAR=value words.
desktop_program() {
  local id=$1 dir line word in_entry
  local -a dirs words
  IFS=: read -r -a dirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for dir in "${dirs[@]}"; do
    if [[ -z $dir || ! -r $dir/applications/$id ]]; then continue; fi
    in_entry=false
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}
      if [[ $line == '['*']' ]]; then
        if [[ $line == '[Desktop Entry]' ]]; then in_entry=true; else in_entry=false; fi
      elif $in_entry && [[ $line =~ ^Exec[[:space:]]*= ]]; then
        read -r -a words <<<"${line#*=}"
        for word in "${words[@]}"; do
          word=${word#\"}
          word=${word%\"}
          if [[ $word == env || $word == *=* ]]; then continue; fi
          printf '%s\n' "$word"
          return 0
        done
        return 0
      fi
    done <"$dir/applications/$id"
    return 0
  done
  return 0
}

# One word in single quotes for sh.
sh_quote() {
  local text=${1//\'/\'\\\'\'}
  printf "'%s'" "$text"
}

# The command as a one-shot script, for terminals whose -e is not known to
# take the rest of the arguments as they are: some take exactly one word
# (xfce4-terminal, Terminator), some a line for the shell. The script's path
# is the same single word for all of them. It lives in the runtime directory
# (the user's alone) and removes itself as it starts.
command_script() {
  local dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}} file word words=""
  if [[ ! -d $dir || ! -w $dir || $dir == *[[:space:]]* ]]; then dir=/tmp; fi
  file=$(mktemp "$dir/buchhwin-terminal.XXXXXX")
  for word in "$@"; do words+=" $(sh_quote "$word")"; done
  {
    printf '#!/bin/sh\n# One window'"'"'s command, from launch-terminal.sh.\nrm -f -- "$0"\n'
    printf 'set --%s\n' "$words"
    if $hold; then printf '%s\n' "$hold_script"; else printf 'exec "$@"\n'; fi
  } >"$file"
  chmod 700 "$file"
  printf '%s\n' "$file"
}

# The terminal is looked up in bash (scripts/lib/default-terminal.sh, the
# rule of default-apps.py, which takes 20-85 ms to start for the same answer);
# Python only for what bash cannot answer for certain (status 2), or without
# the library.
desktop_id=""
asked=false
if [[ -r $project_dir/scripts/lib/default-terminal.sh ]]; then
  # shellcheck source=lib/default-terminal.sh
  source "$project_dir/scripts/lib/default-terminal.sh"
  if declare -F default_terminal >/dev/null && desktop_id=$(default_terminal); then asked=true; fi
fi
if ! $asked; then
  desktop_id=$(python3 "$project_dir/scripts/default-apps.py" get terminal 2>/dev/null) || desktop_id=""
fi
case $desktop_id in
  "") program="" ;;
  Alacritty.desktop) program=alacritty ;;
  kitty.desktop) program=kitty ;;
  org.kde.konsole.desktop) program=konsole ;;
  foot.desktop | footclient.desktop | org.codeberg.dnkl.foot.desktop | org.codeberg.dnkl.footclient.desktop) program=foot ;;
  org.wezfurlong.wezterm.desktop) program=wezterm ;;
  com.mitchellh.ghostty.desktop) program=ghostty ;;
  org.gnome.Terminal.desktop) program=gnome-terminal ;;
  xterm.desktop) program=xterm ;;
  uxterm.desktop) program=uxterm ;;
  *) program=$(desktop_program "$desktop_id") || program="" ;;
esac
case ${program##*/} in
  # A Flatpak's terminal sees neither the one-shot script nor the host's
  # programs, and `flatpak run` takes no -e.
  "" | flatpak) kind=kitty ;;
  alacritty | kitty | konsole | ghostty | gnome-terminal) kind=${program##*/} ;;
  # footclient needs a running server and returns while the window is
  # still open: foot itself is the same terminal in a process of its own.
  foot | footclient) kind=foot; program=${program%client} ;;
  wezterm | wezterm-gui) kind=wezterm; program=${program%-gui} ;;
  xterm | uxterm) kind=xterm ;;
  *) kind=other ;;
esac
# kitty and Alacritty start through their launchers, by name.
if [[ $kind == alacritty ]]; then program=alacritty; fi
if [[ $kind != kitty ]] && ! command -v "$program" >/dev/null 2>&1; then
  kind=kitty
fi
app_id=${desktop_id%.desktop}
unit_args=()
if [[ -n $unit ]]; then unit_args=(--unit "$unit"); fi
app=("$project_dir/scripts/launch-app.sh" "${unit_args[@]}" "$app_id")

case $kind in
  kitty)
    run=("$project_dir/scripts/launch-kitty.sh" "${unit_args[@]}")
    if $hold; then run+=(--hold); fi
    if [[ -n $title ]]; then run+=(--title "$title"); fi
    run+=("$@") ;;
  alacritty)
    run=("$project_dir/scripts/launch-alacritty.sh" "${unit_args[@]}")
    if $hold; then run+=(--hold); fi
    if [[ -n $title ]]; then run+=(--title "$title"); fi
    if (( $# )); then run+=(-e "$@"); fi ;;
  konsole)
    run=("${app[@]}" "$program" --nofork)
    if $hold; then run+=(--hold); fi
    # Konsole's window title is its tab's.
    if [[ -n $title ]]; then run+=(-p "tabtitle=$title"); fi
    if (( $# )); then run+=(-e "$@"); fi ;;
  foot)
    run=("${app[@]}" "$program")
    if $hold; then run+=(--hold); fi
    if [[ -n $title ]]; then run+=("--title=$title"); fi
    if (( $# )); then run+=(-- "$@"); fi ;;
  wezterm)
    # No title of its own on the command line.
    run=("${app[@]}" "$program" start --always-new-process)
    if $hold; then run+=(-- sh -c "$hold_script" sh "$@")
    elif (( $# )); then run+=(-- "$@"); fi ;;
  ghostty)
    # Through the one-shot script, so its -e gets a single word whatever it
    # does with more.
    run=("${app[@]}" "$program")
    if [[ -n $title ]]; then run+=("--title=$title"); fi
    if (( $# )); then run+=(-e "$(command_script "$@")"); fi ;;
  gnome-terminal)
    run=("${app[@]}" "$program" --wait)
    if [[ -n $title ]]; then run+=("--title=$title"); fi
    if $hold; then run+=(-- sh -c "$hold_script" sh "$@")
    elif (( $# )); then run+=(-- "$@"); fi ;;
  xterm)
    run=("${app[@]}" "$program")
    if $hold; then run+=(-hold); fi
    if [[ -n $title ]]; then run+=(-T "$title"); fi
    if (( $# )); then run+=(-e "$@"); fi ;;
  *)
    run=("${app[@]}" "$program")
    if (( $# )); then run+=(-e "$(command_script "$@")"); fi ;;
esac
exec "${run[@]}"
