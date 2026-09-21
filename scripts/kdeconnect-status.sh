#!/usr/bin/env bash
set -uo pipefail

# Read-only KDE Connect snapshot for Settings > Phone, read from the daemon's
# D-Bus API with busctl (`kdeconnect-cli -l` sleeps 2 s and starts a network
# discovery on every call). Prints sections that
# services/kdeconnect/KdeConnectLogic.js parses:
#   @daemon running|stopped
#   @self / @name / @devices / @requests    busctl JSON of the daemon
#   @device ID / @battery ID / @key ID      busctl JSON per device
# and, for paired devices that are connected, the plugin objects:
#   @connectivity ID    cellular network type and signal strength
#   @mpris ID           the phone's media players (mprisremote)
#   @lock ID            lockdevice state
#   @notify ID          ids of the mirrored notifications, never their text
#   @commands ID        the commands the phone offers, as its own JSON
#   @sftp ID            whether the phone is mounted over SFTP
# Nothing is queried while kdeconnectd is not running: the daemon is D-Bus
# activatable, so a call would start it.
bus=(busctl --user --json=short --auto-start=no --timeout=3)
service=org.kde.kdeconnect
daemon=(/modules/kdeconnect org.kde.kdeconnect.daemon)
props=org.freedesktop.DBus.Properties

if ! pgrep -u "$(id -u)" -x kdeconnectd >/dev/null 2>&1; then
  printf '@daemon stopped\n'
  exit 0
fi
printf '@daemon running\n'
section() {
  local name=$1
  shift
  printf '%s\n' "$name"
  "${bus[@]}" "$@" 2>/dev/null
  printf '\n'
}
section @self call "$service" "${daemon[@]}" selfId
section @name call "$service" "${daemon[@]}" announcedName
devices=$("${bus[@]}" call "$service" "${daemon[@]}" deviceNames bb false false 2>/dev/null)
printf '@devices\n%s\n' "$devices"
section @requests get-property "$service" "${daemon[@]}" pairingRequests

while IFS= read -r id; do
  # Device ids become D-Bus object path elements.
  case $id in '' | *[!A-Za-z0-9_]*) continue ;; esac
  path=/modules/kdeconnect/devices/$id
  device=$("${bus[@]}" call "$service" "$path" "$props" GetAll s org.kde.kdeconnect.device 2>/dev/null)
  printf '@device %s\n%s\n\n' "$id" "$device"
  section "@battery $id" call "$service" "$path/battery" "$props" GetAll s org.kde.kdeconnect.device.battery
  section "@key $id" call "$service" "$path" org.kde.kdeconnect.device verificationKey
  # Plugin objects only exist while a paired device is connected; asking an
  # unreachable or unpaired one would only produce "Unknown object" errors.
  connected=$(jq -r 'if (.data[0].isPaired.data == true and .data[0].isReachable.data == true)
                     then "yes" else "no" end' <<<"$device" 2>/dev/null)
  [ "$connected" = yes ] || continue
  section "@connectivity $id" call "$service" "$path/connectivity_report" "$props" GetAll s org.kde.kdeconnect.device.connectivity_report
  section "@mpris $id" call "$service" "$path/mprisremote" "$props" GetAll s org.kde.kdeconnect.device.mprisremote
  section "@lock $id" call "$service" "$path/lockdevice" "$props" GetAll s org.kde.kdeconnect.device.lockdevice
  section "@notify $id" call "$service" "$path/notifications" org.kde.kdeconnect.device.notifications activeNotifications
  # The commands the phone offers (runcommand plugin) and whether it is
  # mounted over SFTP. Both are read-only; nothing is triggered or mounted here.
  section "@commands $id" get-property "$service" "$path/remotecommands" org.kde.kdeconnect.device.remotecommands commands
  section "@sftp $id" call "$service" "$path/sftp" org.kde.kdeconnect.device.sftp isMounted
done < <(jq -r '.data[0] // {} | keys[]' <<<"$devices" 2>/dev/null)
printf '@end\n'
