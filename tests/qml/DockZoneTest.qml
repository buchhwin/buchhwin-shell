import Quickshell
import QtQuick
import QtQuick.Layouts
import "Harness.js" as T
import "../../services/dock/DockLogic.js" as D

// The patterns the dock's zones and its service are built on (shell/dock/
// DockZone.qml, services/DockService.qml), with stand-ins for the pills: the
// real ones need the layout and the dock's service, and those reach the
// session (testing.md pitfall 82).
//
// - A hidden dock hides its content, and every pill under it then reads
//   `visible: false` (pitfall 89). A zone that counted `visible` pills came
//   to none, and the hidden dock's body - its reveal strip and its
//   intellihide rect - shrank to its padding (ui-dock#0). The zone counts
//   the pills' own `hasContent` (DockLogic.shownCount).
// - A Grid with more columns than children counted one gap too many after
//   the last pill, and the dock stood off its centre (D6); a GridLayout of
//   one row does not, also with a pill that shows nothing.
// - DesktopEntries.byId() notifies no binding when the entries arrive
//   (perf#3): a binding that also reads a revision the service moves on
//   every scan resolves again.
ShellRoot {
    id: root
    readonly property int gap: 9
    readonly property int pillLength: 30

    function pills() { return Array.from({ length: repeater.count }, (_, index) => repeater.itemAt(index)) }
    function visibleCount() { return pills().filter(pill => pill && pill.visible).length }

    // The entries as DesktopEntries holds them: filled without telling anyone.
    property var entries: ({ map: {} })
    function byId(id) { return entries.map[id] || null }
    property int revision: 0
    // How often each binding ran, kept where writing it notifies nothing.
    property var runs: ({ plain: 0, revised: 0 })
    readonly property var plain: { root.runs.plain += 1; return root.byId("org.kde.dolphin") }
    readonly property var revised: { root.runs.revised += 1; const unused = root.revision; return root.byId("org.kde.dolphin") }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 120

        Item {
            id: content
            GridLayout {
                id: zone
                columns: 1000
                rows: 1
                columnSpacing: root.gap
                rowSpacing: root.gap
                Repeater {
                    id: repeater
                    model: [true, false, true]
                    Rectangle {
                        required property var modelData
                        readonly property bool hasContent: modelData
                        visible: hasContent
                        implicitWidth: root.pillLength
                        implicitHeight: 10
                    }
                }
            }
        }
    }

    Timer {
        id: measure
        interval: 100
        running: true
        onTriggered: {
            const expected = 2 * root.pillLength + root.gap
            T.eq(zone.implicitWidth, expected, "one gap between the two pills that show, none after the last (D6)")
            T.eq(D.shownCount(root.pills()), 2, "two pills show")
            T.eq(root.visibleCount(), 2, "and read visible")
            content.visible = false
            hidden.start()
        }
    }
    Timer {
        id: hidden
        interval: 50
        onTriggered: {
            T.eq(root.visibleCount(), 0, "under the hidden content every pill reads invisible")
            T.eq(D.shownCount(root.pills()), 2, "the zone still counts two (ui-dock#0)")
            T.eq(zone.implicitWidth, 2 * root.pillLength + root.gap, "and keeps its length")
            content.visible = true

            T.eq(root.plain, null, "no entries yet")
            root.entries.map["org.kde.dolphin"] = { id: "org.kde.dolphin" }
            const plainBefore = root.runs.plain
            root.revision += 1
            T.eq(root.revised !== null && root.revised.id, "org.kde.dolphin", "a binding that reads the revision resolves again (perf#3)")
            T.eq(root.runs.plain, plainBefore, "one that does not never does")
            T.eq(root.plain, null, "and keeps what it found before the scan")
            T.finish("DockZoneTest")
        }
    }
}
