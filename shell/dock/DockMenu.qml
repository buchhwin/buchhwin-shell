import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/dock/DockLogic.js" as Logic

// An app's menu on the dock: its windows (to the front - a minimized one back
// to its workspace), minimize and restore them, a new window and the entry's
// own actions (a browser's private window, a web app's "New message"), where
// it opens and its window kept on top, pin or unpin, close. Opened by a right
// click or the menu key on an icon, beside it on the dock's screen
// (DockService.openMenu); it does not dim the screen, as a menu does not, and
// a click anywhere else closes it.
//
// Built on the first open (shell.qml's LazyLoader, PanelService.demanded) and
// let go with the dock; the body only while it is open, so the dock's
// service is not asked anything while the dock is off.
//
// Opened by the menu key while the dock has the keyboard, it holds the keys
// for the dock (DockService.keysWithMenu), and an Escape gives them back.
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
    onEscapePressed: DockService.noteMenuEscape()

    Loader {
        id: body
        width: parent.width
        active: root.shown
        sourceComponent: Component {
            ColumnLayout {
                id: column
                spacing: Metrics.spaceXs
                readonly property string key: String(root.openArgs.key || "")
                // As the dock it came out of shows it: its own screen's
                // windows when the docks show their screen's apps.
                readonly property var app: DockService.itemFor(key, root.dockScreen)
                readonly property var entry: DockService.entryOf(app)
                readonly property var rows: Logic.menuRows(app, entry ? entry.actions : [], LayoutService.dockPinsFull,
                                                           Metrics.dockMenuWindows, entry ? entry.command : [], { minimize: true })
                // Where the app opens from now on (Settings > Apps > Open on):
                // this dock's screen and the workspace it shows - or, when that
                // is its place already, wherever you are again.
                readonly property var here: entry ? SessionAppsService.hereFor(entry.id, root.dockScreen) : null
                // An app with one window that is not minimized: that window
                // kept on top, floated and pinned to every workspace
                // (Super+Ctrl+T), or let go again.
                readonly property var lone: app !== null && (app.windows || []).length === 1
                                            && app.windows[0].minimized !== true ? app.windows[0] : null
                // The rows in their order: the windows and the app's own,
                // then where it opens and the window on top, then pinning and
                // closing - closing last, as in any menu, with nothing harmless
                // right under it.
                readonly property var shownRows: {
                    const tail = rows.filter(row => row.kind === "pin" || row.kind === "unpin" || row.kind === "close")
                    const extra = []
                    if (here !== null) extra.push({ kind: "here" })
                    if (lone !== null) extra.push({ kind: "top", address: lone.address })
                    return rows.filter(row => tail.indexOf(row) < 0).concat(extra, tail)
                }
                // The app went (its last window closed, it was unpinned).
                onAppChanged: if (root.wanted && app === null) PanelService.close("dockMenu")
                // Whether the window is on top now is Hyprland's record, read
                // once as the menu opens.
                Component.onCompleted: DockService.readWindows()

                PanelHeader {
                    Layout.fillWidth: true
                    title: column.app ? column.app.name : ""
                    subtitle: column.app && column.app.count > 0
                        ? (column.app.count === 1 ? "1 window" : column.app.count + " windows")
                        : column.app && column.app.pinned ? "Pinned" : ""
                    role: "title"
                }

                Repeater {
                    model: column.shownRows
                    ListRow {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        compact: true
                        focusOnTab: true
                        // The windows' titles are the windows' own strings:
                        // ListRow draws them as plain text.
                        readonly property string windowTitle: modelData.kind === "window" ? DockService.titleOf(modelData.address) : ""
                        readonly property bool onTop: modelData.kind === "top" && DockService.keptOnTop(modelData.address)
                        // A window row is a window, minimized or not (its
                        // subtitle says which); Restore has a glyph of its own.
                        icon: modelData.kind === "window" ? Icons.window
                            : modelData.kind === "minimize" ? Icons.minimize
                            : modelData.kind === "restore" ? Icons.restore
                            : modelData.kind === "new" ? Icons.add
                            : modelData.kind === "action" ? Icons.forward
                            : modelData.kind === "here" ? Icons.location
                            : modelData.kind === "top" ? Icons.keepOnTop
                            : modelData.kind === "pin" ? Icons.pin
                            : modelData.kind === "unpin" ? Icons.unpin
                            : modelData.kind === "close" ? Icons.close : ""
                        title: modelData.kind === "window" ? (row.windowTitle.length ? row.windowTitle : "Window")
                            : modelData.kind === "more" ? modelData.count + " more"
                            : modelData.kind === "minimize" ? (modelData.count > 1 ? "Minimize " + modelData.count + " windows" : "Minimize")
                            : modelData.kind === "restore" ? (modelData.count > 1 ? "Restore " + modelData.count + " windows" : "Restore")
                            : modelData.kind === "new" ? "New window"
                            : modelData.kind === "action" ? modelData.name
                            : modelData.kind === "here" ? (column.here && column.here.on ? "Open wherever you are" : "Always open here")
                            : modelData.kind === "top" ? (row.onTop ? "Stop keeping on top" : "Keep on top")
                            : modelData.kind === "pin" ? "Pin to dock"
                            : modelData.kind === "unpin" ? "Unpin"
                            : modelData.kind === "close" ? (modelData.count > 1 ? "Close " + modelData.count + " windows" : "Close window")
                            : ""
                        subtitle: modelData.kind === "window" ? Logic.workspaceLabel(modelData.workspace, modelData.workspaceName,
                                                                                     modelData.monitor, HyprlandService.blockOrder)
                            : modelData.kind === "here" ? (column.here ? column.here.text : "")
                            : modelData.kind === "pin" && modelData.reason === "hidden" ? "Not shown in the app list"
                            : modelData.kind === "pin" && modelData.enabled === false ? "At most " + LayoutService.dockPinLimit + " apps on the dock" : ""
                        interactive: modelData.kind !== "more" && !(modelData.kind === "pin" && modelData.enabled === false)
                        onClicked: root.run(modelData, column.entry)
                    }
                }
            }
        }
    }

    // The screen of the dock the menu came out of.
    readonly property string dockScreen: String(openArgs.onScreen || "")

    function run(row, entry) {
        const key = String(openArgs.key || "")
        switch (row.kind) {
        case "here": if (entry) SessionAppsService.toggleHere(entry.id, dockScreen); break
        case "top": HyprlandService.keepOnTop(row.address); break
        case "window": DockService.focusWindow(row.address); break
        case "minimize": DockService.minimizeWindows(key, dockScreen); break
        case "restore": DockService.restoreWindows(key, dockScreen); break
        case "new": DockService.newWindow(key); break
        case "action": DockService.runAction(key, row.id); break
        case "pin": case "unpin": DockService.togglePin(key); break
        case "close": DockService.closeWindows(key, dockScreen); break
        }
        if (row.kind !== "window" && row.kind !== "restore") PanelService.close("dockMenu")
    }
}
