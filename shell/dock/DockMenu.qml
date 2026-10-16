import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/DockLogic.js" as Logic

// An app's menu on the dock: its windows (to the front), a new window and the
// entry's own actions (a browser's private window, a web app's "New
// message"), pin or unpin, close. Opened by a right click or the menu key on
// an icon, beside it on the dock's screen (DockService.openMenu); it does not
// dim the screen, as a menu does not, and a click anywhere else closes it.
//
// The body is only built while it is open: the panel exists from the start,
// and the dock's service is not asked anything while the dock is off.
ShellPanel {
    id: root
    panelId: "dockMenu"
    placement: "top-right"
    cardWidth: Metrics.dockMenuWidth
    scrimColor: "transparent"
    followClock: false
    followBarSpot: false
    outOfNotch: false
    keyNavigation: true

    Loader {
        id: body
        width: parent.width
        active: root.shown
        sourceComponent: Component {
            ColumnLayout {
                id: column
                spacing: Metrics.spaceXs
                readonly property string key: String(root.openArgs.key || "")
                readonly property var app: DockService.itemFor(key)
                readonly property var entry: DockService.entryOf(app)
                readonly property var rows: Logic.menuRows(app, entry ? entry.actions : [], LayoutService.dockPinsFull,
                                                           Metrics.dockMenuWindows)
                // The app went (its last window closed, it was unpinned).
                onAppChanged: if (root.wanted && app === null) PanelService.close("dockMenu")

                PanelHeader {
                    Layout.fillWidth: true
                    title: column.app ? column.app.name : ""
                    subtitle: column.app && column.app.count > 0
                        ? (column.app.count === 1 ? "1 window" : column.app.count + " windows")
                        : column.app && column.app.pinned ? "Pinned" : ""
                    role: "title"
                }

                Repeater {
                    model: column.rows
                    ListRow {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        compact: true
                        focusOnTab: true
                        // The windows' titles are the windows' own strings:
                        // ListRow draws them as plain text.
                        readonly property string windowTitle: modelData.kind === "window" ? DockService.titleOf(modelData.address) : ""
                        icon: modelData.kind === "window" ? Icons.window
                            : modelData.kind === "new" ? Icons.add
                            : modelData.kind === "action" ? Icons.forward
                            : modelData.kind === "pin" ? Icons.pin
                            : modelData.kind === "unpin" ? Icons.unpin
                            : modelData.kind === "close" ? Icons.close : ""
                        title: modelData.kind === "window" ? (row.windowTitle.length ? row.windowTitle : "Window")
                            : modelData.kind === "more" ? modelData.count + " more"
                            : modelData.kind === "new" ? "New window"
                            : modelData.kind === "action" ? modelData.name
                            : modelData.kind === "pin" ? "Pin to dock"
                            : modelData.kind === "unpin" ? "Unpin"
                            : modelData.kind === "close" ? (modelData.count > 1 ? "Close " + modelData.count + " windows" : "Close window")
                            : ""
                        subtitle: modelData.kind === "window" ? "Workspace " + modelData.workspace
                            : modelData.kind === "pin" && modelData.enabled === false ? "At most " + LayoutService.dockPinLimit + " apps on the dock" : ""
                        interactive: modelData.kind !== "more" && !(modelData.kind === "pin" && modelData.enabled === false)
                        onClicked: root.run(modelData)
                    }
                }
            }
        }
    }

    function run(row) {
        const key = String(openArgs.key || "")
        switch (row.kind) {
        case "window": DockService.focusWindow(row.address); break
        case "new": DockService.newWindow(key); break
        case "action": DockService.runAction(key, row.id); break
        case "pin": case "unpin": DockService.togglePin(key); break
        case "close": DockService.closeWindows(key); break
        }
        if (row.kind !== "window") PanelService.close("dockMenu")
    }
}
