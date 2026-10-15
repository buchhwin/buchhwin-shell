pragma Singleton
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Singleton {
    // StatusNotifier ids the shell does not show. nm-applet's icon repeats the
    // shell's own network widget; the applet keeps running all the same, as
    // the session's only NetworkManager secret agent - the one that asks for
    // Wi-Fi and VPN passwords - which is why scripts/lib/autostart-skip.sh
    // leaves it alone.
    readonly property var hiddenIds: ["nm-applet"]
    readonly property var items: SystemTray.items.values.filter(item => hiddenIds.indexOf(item.id) < 0)
}
