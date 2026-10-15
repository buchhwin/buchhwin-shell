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
#   print-applet                     system-config-printer's print queue applet,
#                                    ~42 MB of Python for a tray icon; its entry
#                                    says NotShowIn=KDE;GNOME;Cinnamon, so it
#                                    started here and never under Plasma
# Not nm-applet, however much it looks like one more of these: it is the
# session's only NetworkManager secret agent, and without it no Wi-Fi or VPN
# password is asked for. Its tray icon is hidden in services/TrayService.qml.
BUCHHWIN_AUTOSTART_SKIP=(geoclue-demo-agent sealertauto org.freedesktop.problems.applet print-applet)

# Prints the generated unit name of every skipped entry, one per line.
autostart_skip_units() {
  local name
  for name in "${BUCHHWIN_AUTOSTART_SKIP[@]}"; do
    printf 'app-%s@autostart.service\n' "$(systemd-escape -- "$name")"
  done
}
