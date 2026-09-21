# shellcheck shell=bash
# XDG autostart entries that are useless in buchhwin-shell. systemd's
# xdg-autostart generator turns every matching /etc/xdg/autostart entry into
# app-<escaped name>@autostart.service; session-init.sh masks these units for
# the running user manager only (`mask --runtime`, nothing under ~/.config),
# and session/buchhwin-shell-session unmasks them when the session ends, so
# Plasma keeps starting them. Source this file.
#   geoclue-demo-agent               GeoClue demo agent (the shell asks for no location)
#   sealertauto                      SELinux troubleshooter applet
#   org.freedesktop.problems.applet  ABRT problem reporting applet
BUCHHWIN_AUTOSTART_SKIP=(geoclue-demo-agent sealertauto org.freedesktop.problems.applet)

# Prints the generated unit name of every skipped entry, one per line.
autostart_skip_units() {
  local name
  for name in "${BUCHHWIN_AUTOSTART_SKIP[@]}"; do
    printf 'app-%s@autostart.service\n' "$(systemd-escape -- "$name")"
  done
}
