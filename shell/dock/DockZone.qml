import Quickshell
import QtQuick
import qs.theme
import qs.services
import qs.shell.bar
import "../../services/bar/BarLogic.js" as BarLogic
import "../../services/model/KeyedLogic.js" as Keyed

// One of the dock's three zones (LayoutService.dockLayout.left/center/right):
// its pills in a line, drawn as the bar draws a flat bar's pills, with a line
// between groups. Dock.qml places it.
Grid {
    id: root
    required property string zone
    // The dock's window (Dock.qml): its scale, direction, thickness, origin.
    required property var dock

    readonly property var pills: LayoutService.dockLayout[zone] || []
    // How many of its pills show anything: an empty zone takes no room.
    property int visibleCount: 0
    columns: dock.vertical ? 1 : 1000
    spacing: Metrics.barGroupGap * dock.widgetScale

    // The pills, each keyed by all of itself and the options it is drawn
    // with, handed back as the very same objects while nothing changed
    // (KeyedLogic, pitfall 76) - PillBar's way.
    property var store: ({ list: [] })
    function kept(next) {
        const list = Keyed.keep(store.list, next, "pillKey")
        store.list = list
        return list
    }
    function pillKeys(list) {
        const options = JSON.stringify([dock.widgetScale, dock.vertical, dock.across])
        const seen = {}
        return (list || []).map(pill => {
            const text = JSON.stringify(pill) + options
            seen[text] = (seen[text] || 0) + 1
            return Object.assign({ pillKey: text + "#" + seen[text] }, pill)
        })
    }
    function recount() {
        let count = 0
        for (let index = 0; index < repeater.count; ++index) {
            const pill = repeater.itemAt(index)
            if (pill && pill.visible) count += 1
        }
        visibleCount = count
    }
    readonly property var flags: BarLogic.separators(Array.from({ length: repeater.count }, (_, i) => {
        const pill = repeater.itemAt(i)
        return pill !== null && pill.visible
    }))

    // A pill reports where it is when it moves within its zone; when the
    // whole zone moves (the end zone after a pill left it) it does not see
    // it, and the editor's frames stayed where the pills had been.
    function reportPills() {
        for (let index = 0; index < repeater.count; ++index) {
            const pill = repeater.itemAt(index)
            if (pill) pill.reportRects()
        }
    }
    onXChanged: { Qt.callLater(dock.reportZones); Qt.callLater(reportPills) }
    onYChanged: { Qt.callLater(dock.reportZones); Qt.callLater(reportPills) }
    onWidthChanged: { Qt.callLater(dock.reportZones); Qt.callLater(recount) }
    onHeightChanged: { Qt.callLater(dock.reportZones); Qt.callLater(recount) }

    Repeater {
        id: repeater
        model: ScriptModel { values: root.kept(root.pillKeys(root.pills)); objectProp: "pillKey" }
        onItemAdded: Qt.callLater(root.recount)
        onItemRemoved: Qt.callLater(root.recount)
        Pill {
            required property var modelData
            required property int index
            pill: modelData
            screenName: root.dock.screenName
            scaleFactor: root.dock.widgetScale
            flat: true
            barRadius: 0
            vertical: root.dock.vertical
            barThickness: root.dock.across
            reportOrigin: ({ x: root.dock.origin.x, y: root.dock.origin.y })
            surface: "dock"
            dockEdge: root.dock.edge
            separator: root.flags[index] === true
            wiggleIndex: index
            onVisibleChanged: Qt.callLater(root.recount)
        }
    }
}
