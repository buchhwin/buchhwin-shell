#!/usr/bin/env bash
set -uo pipefail

# Read-only account snapshot for Settings > Accounts. KDE PIM (Akonadi) owns
# the accounts; this script only reads its AgentManager D-Bus API with busctl.
# Akonadi is never started here: the server is D-Bus activatable, so every call
# uses --auto-start=no and nothing is queried while akonadi_control is not
# running. Sections that services/accounts/AccountsLogic.js parses:
#   @tools NAME…              account wizards found in PATH
#   @server running|stopped
#   @agents ID…               every agent instance, resources or not
#   @type TYPE_ID             "key <busctl JSON>" lines (name, comment, icon,
#   @instance INSTANCE_ID      caps, mime / type, name, status, message,
#                              online, progress)
# Only agent types with the "Resource" capability become accounts; the mail
# filter, indexer and the other internal agents are skipped.
# Account names appear in this output for the shell UI only; the service never
# logs them and the IPC output carries counts, ids and states.
#
#   accounts-status.sh                  the whole snapshot
#   accounts-status.sh --status ID…     @server, @agents and, for the given
#                                       instances, only name, status, message,
#                                       online and progress
#
# The second form is the page's poll every 10 s. A type's name, comment, icon,
# MIME types and capabilities and an instance's type never change while the
# instance exists, and they were most of the ~55 busctl calls of every poll;
# the shell keeps them from the whole snapshot and reads that again when
# @agents says an instance came or went.

bus=(busctl --user --json=short --auto-start=no --timeout=3)
service=org.freedesktop.Akonadi.Control
manager=(/AgentManager org.freedesktop.Akonadi.AgentManager)

status_only=0
wanted=()
if [[ ${1:-} == --status ]]; then
  status_only=1
  shift
  for id in "$@"; do
    case $id in '' | *[!A-Za-z0-9_]*) continue ;; esac
    wanted+=("$id")
  done
fi

if (( ! status_only )); then
  tools=""
  command -v kcmshell6 >/dev/null 2>&1 && tools="$tools kaccounts"
  command -v systemsettings >/dev/null 2>&1 && tools="$tools systemsettings"
  command -v accountwizard >/dev/null 2>&1 && tools="$tools accountwizard"
  printf '@tools%s\n' "$tools"
fi

# Whether Akonadi runs is asked of the bus (NameHasOwner starts nothing): the
# name is what every call below needs, and pgrep read all of /proc for it.
owner=$(busctl --user --auto-start=no --timeout=3 call org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus NameHasOwner s "$service" 2>/dev/null)
if [[ $owner != "b true" ]]; then
  printf '@server stopped\n'
  exit 0
fi
printf '@server running\n'

call() {
  "${bus[@]}" call "$service" "${manager[@]}" "$@" 2>/dev/null
}

# {"type":"s","data":["value"]} → value
unwrap() {
  local text=$1
  case $text in
    *'["'*) text=${text##*\[\"} ;;
    *) printf '' ; return ;;
  esac
  printf '%s' "${text%%\"*}"
}

instance_status() {
  printf '@instance %s\n' "$1"
  printf 'name %s\n' "$(call agentInstanceName s "$1")"
  printf 'status %s\n' "$(call agentInstanceStatus s "$1")"
  printf 'message %s\n' "$(call agentInstanceStatusMessage s "$1")"
  printf 'online %s\n' "$(call agentInstanceOnline s "$1")"
  printf 'progress %s\n' "$(call agentInstanceProgress s "$1")"
}

instances=$(call agentInstances)
case $instances in
  *'[['*) ids=${instances#*\[\[} ; ids=${ids%%\]\]*} ;;
  *) ids="" ;;
esac
ids=$(printf '%s' "$ids" | tr ',' '\n' | tr -d '"')

agents=""
while IFS= read -r id; do
  case $id in '' | *[!A-Za-z0-9_]*) continue ;; esac
  agents="$agents $id"
done <<< "$ids"
printf '@agents%s\n' "$agents"

if (( status_only )); then
  for id in "${wanted[@]}"; do
    case " $agents " in
      *" $id "*) instance_status "$id" ;;
    esac
  done
  exit 0
fi

seen=""
resources=""
while IFS= read -r id; do
  case $id in '' | *[!A-Za-z0-9_]*) continue ;; esac
  type_json=$(call agentInstanceType s "$id")
  type=$(unwrap "$type_json")
  case $type in '' | *[!A-Za-z0-9_]*) continue ;; esac

  case " $seen " in
    *" $type "*) ;;
    *)
      seen="$seen $type"
      caps=$(call agentCapabilities s "$type")
      case $caps in
        *'"Resource"'*)
          resources="$resources $type"
          printf '@type %s\n' "$type"
          printf 'name %s\n' "$(call agentName s "$type")"
          printf 'comment %s\n' "$(call agentComment s "$type")"
          printf 'icon %s\n' "$(call agentIcon s "$type")"
          printf 'mime %s\n' "$(call agentMimeTypes s "$type")"
          printf 'caps %s\n' "$caps"
          ;;
      esac
      ;;
  esac

  case " $resources " in
    *" $type "*)
      instance_status "$id"
      printf 'type %s\n' "$type_json"
      ;;
  esac
done <<< "$ids"
