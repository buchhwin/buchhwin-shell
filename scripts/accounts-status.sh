#!/usr/bin/env bash
set -uo pipefail

# Read-only account snapshot for Settings > Accounts. KDE PIM (Akonadi) owns
# the accounts; this script only reads its AgentManager D-Bus API with busctl.
# Akonadi is never started here: the server is D-Bus activatable, so every call
# uses --auto-start=no and nothing is queried while akonadi_control is not
# running. Sections that services/accounts/AccountsLogic.js parses:
#   @tools NAME…              account wizards found in PATH
#   @server running|stopped
#   @type TYPE_ID             "key <busctl JSON>" lines (name, comment, icon,
#   @instance INSTANCE_ID      caps, mime / type, name, status, message,
#                              online, progress)
# Only agent types with the "Resource" capability become accounts; the mail
# filter, indexer and the other internal agents are skipped.
# Account names appear in this output for the shell UI only; the service never
# logs them and the IPC output carries counts, ids and states.

bus=(busctl --user --json=short --auto-start=no --timeout=3)
service=org.freedesktop.Akonadi.Control
manager=(/AgentManager org.freedesktop.Akonadi.AgentManager)

tools=""
command -v kcmshell6 >/dev/null 2>&1 && tools="$tools kaccounts"
command -v systemsettings >/dev/null 2>&1 && tools="$tools systemsettings"
command -v accountwizard >/dev/null 2>&1 && tools="$tools accountwizard"
printf '@tools%s\n' "$tools"

if ! pgrep -u "$(id -u)" -x akonadi_control >/dev/null 2>&1; then
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

instances=$(call agentInstances)
case $instances in
  *'[['*) ids=${instances#*\[\[} ; ids=${ids%%\]\]*} ;;
  *) ids="" ;;
esac
ids=$(printf '%s' "$ids" | tr ',' '\n' | tr -d '"')

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
      printf '@instance %s\n' "$id"
      printf 'type %s\n' "$type_json"
      printf 'name %s\n' "$(call agentInstanceName s "$id")"
      printf 'status %s\n' "$(call agentInstanceStatus s "$id")"
      printf 'message %s\n' "$(call agentInstanceStatusMessage s "$id")"
      printf 'online %s\n' "$(call agentInstanceOnline s "$id")"
      printf 'progress %s\n' "$(call agentInstanceProgress s "$id")"
      ;;
  esac
done <<< "$ids"
