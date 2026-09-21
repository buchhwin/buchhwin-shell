pragma Singleton
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

Singleton {
    readonly property var items: SystemTray.items.values
}
