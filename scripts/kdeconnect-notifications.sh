#!/usr/bin/env bash
set -uo pipefail

# Read-only list of the notifications one phone mirrors, for the notification
# list in Settings > Phone. Runs only while that list is open; the regular
# snapshot (kdeconnect-status.sh) reads the ids alone so a badge can show a
# count without ever reading the text. Sections parsed by
# services/kdeconnect/KdeConnectLogic.js parseNotifications():
#   @item PUBLIC_ID   busctl JSON of one notification's properties
# The contents stay in the shell process: they are never logged and never put
# into IPC output.
id=${1:-}
case $id in '' | *[!A-Za-z0-9_]*)
  printf '@end\n'
  exit 0
  ;;
esac

bus=(busctl --user --json=short --auto-start=no --timeout=3)
service=org.kde.kdeconnect
path=/modules/kdeconnect/devices/$id/notifications
iface=org.kde.kdeconnect.device.notifications

# The daemon is D-Bus activatable, so nothing is called while it is stopped.
if ! pgrep -u "$(id -u)" -x kdeconnectd >/dev/null 2>&1; then
  printf '@end\n'
  exit 0
fi

ids=$("${bus[@]}" call "$service" "$path" "$iface" activeNotifications 2>/dev/null)
count=0
while IFS= read -r note; do
  # Public ids are counter values (NotificationsPlugin::newId), so they are
  # valid object path elements; anything else is skipped.
  case $note in '' | *[!A-Za-z0-9_]*) continue ;; esac
  count=$((count + 1))
  [ "$count" -le 40 ] || break
  printf '@item %s\n' "$note"
  "${bus[@]}" call "$service" "$path/$note" org.freedesktop.DBus.Properties GetAll s \
    org.kde.kdeconnect.device.notifications.notification 2>/dev/null
  printf '\n'
done < <(jq -r '.data[0][]? // empty' <<<"$ids" 2>/dev/null)
printf '@end\n'
