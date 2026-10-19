import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.bar
import "../../services/bar/BarLogic.js" as BarLogic
import "../../services/dock/DockLogic.js" as Logic
import "../../services/model/KeyedLogic.js" as Keyed

// One of the dock's three zones (LayoutService.dockLayout.left/center/right):
// its pills in a line, drawn as the bar draws a flat bar's pills, with a line
// between groups. Dock.qml places it.
//
// A GridLayout of one row (one column on a side dock), as a pill lays out
// its items: a Grid with more columns than children counted one gap too
// many after the last pill, and the dock's row stood off its centre by half
// a gap. A layout counts only the pills that are there, also under the
// hidden content of a hidden dock (testing.md pitfall 89).
GridLayout {
    id: root
    required property string zone
    // The dock's window (Dock.qml): its scale, direction, thickness, origin.
    required property var dock

    readonly property var pills: LayoutService.dockLayout[zone] || []
    // How many of its pills show anything: an empty zone takes no room.
    property int visibleCount: 0
    readonly property real gap: Metrics.barGroupGap * dock.widgetScale
    columns: dock.vertical ? 1 : 1000
    rows: dock.vertical ? 1000 : 1
    columnSpacing: gap
    rowSpacing: gap

    // Whether the apps are in this zone, and the zone's length without them
    // (every other pill, the gaps, the apps pill's own padding): the room
    // the apps are fitted into is measured from this, never from the apps
    // themselves (Dock.qml, DockLogic.appsRoom).
    readonly property bool holdsApps: pills.some(pill => (pill.items || []).some(item => item.type === "apps"))
    readonly property real lengthBesideApps: {
        let length = 0
        let shown = 0
        for (let index = 0; index < repeater.count; ++index) {
            const pill = repeater.itemAt(index)
            if (!pill || !pill.hasContent) continue
            shown += 1
            length += pill.holdsApps ? pill.lengthBesideApps : (dock.vertical ? pill.implicitHeight : pill.implicitWidth)
        }
        return length + Math.max(0, shown - 1) * gap
    }

    // The pills, each keyed by all of itself and the options it is drawn
    // with, handed back as the very same objects while nothing changed
    // (KeyedLogic, pitfall 76) - PillBar's way. And the list itself when not
    // one of them changed (DockLogic.sameObjects): the model is then not
    // handed anything new.
    property var store: ({ list: [] })
    function kept(next) {
        const list = Keyed.keep(store.list, next, "pillKey")
        if (Logic.sameObjects(store.list, list)) return store.list
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
    // Counted by the pills' own condition, not by `visible`: under a hidden
    // dock every pill reads invisible, and a zone that counted those made
    // the hidden dock's body - its reveal strip and its intellihide rect -
    // a dozen pixels long (DockLogic.shownCount).
    function pillsNow() { return Array.from({ length: repeater.count }, (_, index) => repeater.itemAt(index)) }
    function recount() { visibleCount = Logic.shownCount(pillsNow()) }
    readonly property var flags: BarLogic.separators(Logic.shownFlags(pillsNow()))

    // A pill reports where it is when it moves within its zone; when the
    // whole zone moves (the end zone after a pill left it) it does not see
    // it, and the editor's frames stayed where the pills had been. Each pill
    // reports once it has settled, as for its own moves.
    function reportPills() {
        for (let index = 0; index < repeater.count; ++index) {
            const pill = repeater.itemAt(index)
            if (pill) pill.reportSoon()
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
            reportFrame: root.dock.frame
            surface: "dock"
            dockEdge: root.dock.edge
            separator: root.flags[index] === true
            wiggleIndex: index
            onHasContentChanged: Qt.callLater(root.recount)
        }
    }
}
