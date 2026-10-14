#!/usr/bin/env bash
# The KDE wallet as the Secret Service sees it: is the collection open, and if
# it is not, ask ksecretd to open it.
#
#   wallet-unlock.sh status
#       One line, exit 0 open, 1 locked, 2 no secret service on the bus,
#       3 lock state unreadable. Starts nothing.
#   wallet-unlock.sh ensure [--prompt] [--wait S] [--timeout S]
#       Waits up to --wait seconds (default 0) for the wallet's service (below)
#       to have an owner. If the collection is locked, calls Secret.Service.Unlock:
#       a ksecretd that holds the login password (pam_kwallet5) answers with
#       the wallet open, one that does not answers with a prompt path. With
#       --prompt that prompt is followed (Secret.Prompt.Prompt), ksecretd shows
#       its password dialog, and the lock state is polled for up to --timeout
#       seconds (default 60) or until the prompt is gone. Exit codes as for
#       status; the line says what happened:
#         open (already) | open (after unlock) | open (after prompt, N s)
#         locked (no prompt offered) | locked (prompt not followed)
#         locked (prompt dismissed) | locked (timed out) | no service | unreadable
#
# Why one script: session-init.sh (at login), launch-chromium.sh (before
# Brave, Chrome or Chromium) and session-check.sh ask the same question, and
# the answer decides whether the browser may start. Chromium's FreedesktopSecretKeyProvider treats a wallet it
# cannot open as permanently unavailable and encrypts new data with a fallback
# key; that is how Brave ended up logged out of everything on every switch
# between Plasma and this session. Nothing that stores secrets may start
# before this says "open".
#
# Every call is `--auto-start=no`: `busctl status`, or a plain call to an
# activatable name, would start a second ksecretd without the password
# (org.kde.secretservicecompat has a D-Bus service file). `busctl list` only
# reads the bus.
#
# Which name: on Fedora and openSUSE ksecretd owns org.freedesktop.secrets. On
# Arch gnome-keyring usually does - pam_gnome_keyring in /etc/pam.d/sddm and a
# socket unit start it at every login - and it has no kdewallet collection, so
# the generic name would report a wallet that is not this one. ksecretd's own
# name, org.kde.ksecretd, is the same connection and serves the same Secret
# Service objects on every distribution; the generic name only counts when the
# KDE daemon is the one holding it.
set -uo pipefail

collection=/org/freedesktop/secrets/collection/kdewallet
busctl_q() { busctl --user --auto-start=no --no-pager --timeout=3 "$@" 2>/dev/null; }

# The name to talk to, set by owned().
bus=""
owned() {
  bus=$(busctl --user --no-pager list 2>/dev/null | awk '
    $1 == "org.kde.ksecretd" && $2 != "-" { own = 1 }
    $1 == "org.freedesktop.secrets" && $2 != "-" && $3 ~ /^(ksecretd|kwalletd)/ { generic = 1 }
    END { if (own) print "org.kde.ksecretd"; else if (generic) print "org.freedesktop.secrets" }')
  [[ -n $bus ]]
}
# true, false, or nothing when the property cannot be read.
locked() {
  busctl_q get-property "$bus" "$collection" org.freedesktop.Secret.Collection Locked \
    | awk '{ print $2 }'
}
# Asks for the collection to be unlocked. Prints the prompt path from the
# reply ("/" when none was needed), nothing when the call failed or the reply
# ended in anything that is not an object path.
unlock() {
  local path
  path=$(busctl_q call "$bus" /org/freedesktop/secrets org.freedesktop.Secret.Service \
    Unlock ao 1 "$collection" | tail -n 1 | awk '{ print $NF }' | tr -d '"')
  [[ $path == /* ]] && printf '%s\n' "$path"
}
# Follows the prompt: ksecretd shows its dialog and replies at once; the
# outcome shows in the lock state, and the prompt object goes away when the
# dialog is answered or dismissed.
follow() {
  busctl_q call "$bus" "$1" org.freedesktop.Secret.Prompt Prompt s "" >/dev/null
}
prompt_alive() { busctl_q introspect "$bus" "$1" >/dev/null; }

report() { printf '%s\n' "$1"; exit "$2"; }

status() {
  owned || report "no service" 2
  case $(locked) in
    false) report "open" 0 ;;
    true) report "locked" 1 ;;
    *) report "unreadable" 3 ;;
  esac
}

ensure() {
  local prompt=0 wait=0 timeout=60
  while (( $# )); do
    case $1 in
      --prompt) prompt=1 ;;
      --wait) wait=${2:-0}; shift ;;
      --timeout) timeout=${2:-60}; shift ;;
      *) printf 'wallet-unlock: unknown option %s\n' "$1" >&2; exit 64 ;;
    esac
    shift
  done
  local deadline=$(( $(date +%s) + wait ))
  until owned; do
    (( $(date +%s) < deadline )) || report "no service" 2
    sleep 0.1
  done
  local state path started now
  state=$(locked)
  [[ $state == false ]] && report "open (already)" 0
  [[ $state == true ]] || report "unreadable" 3
  path=$(unlock)
  state=$(locked)
  [[ $state == false ]] && report "open (after unlock)" 0
  [[ -n $path && $path != / ]] || report "locked (no prompt offered)" 1
  (( prompt )) || report "locked (prompt not followed)" 1
  follow "$path"
  started=$(date +%s)
  while :; do
    state=$(locked)
    now=$(date +%s)
    [[ $state == false ]] && report "open (after prompt, $(( now - started )) s)" 0
    prompt_alive "$path" || report "locked (prompt dismissed)" 1
    (( now - started < timeout )) || report "locked (timed out)" 1
    sleep 0.5
  done
}

case ${1:-} in
  status) status ;;
  ensure) shift; ensure "$@" ;;
  *) printf 'usage: wallet-unlock.sh status | ensure [--prompt] [--wait S] [--timeout S]\n' >&2; exit 64 ;;
esac
