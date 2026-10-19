import Quickshell
import QtQuick
import QtQuick.Layouts
import "Harness.js" as T
import "../../shell/components"
import qs.theme

// The device and stream lists of the control center, the Bluetooth popup and
// the volume popup keep their rows when the list changes around them. The
// services' lists are new arrays on every change (filters over BlueZ's
// devices and PipeWire's nodes), and a Repeater over such an array - or over
// a list of sections built as new objects - made every section and row again
// whenever discovery found a device or any node came or went: an armed Remove
// fell back to its first click, a slider drag ended under the hand, and the
// Nearby list jumped back to its top.
//
// The pages' shape with the real ScrollList, ListRow, ShellButton and
// ShellSlider: sections by name (strings, built once), rows over a ScriptModel
// of the objects themselves, which keep their identity.
FloatingWindow {
    id: root
    implicitWidth: 480
    implicitHeight: 900

    Component {
        id: deviceType
        QtObject { property string name: ""; property bool paired: false; property bool connected: false }
    }
    property var devices: []
    readonly property var connected: devices.filter(device => device.connected)
    readonly property var paired: devices.filter(device => !device.connected && device.paired)
    readonly property var nearby: devices.filter(device => !device.connected && !device.paired)
    property var nodes: []

    property int rowsBuilt: 0
    property int sectionsBuilt: 0
    property int streamsBuilt: 0
    property var rows: ({})
    property var streams: ({})

    ColumnLayout {
        anchors.fill: parent
        Repeater {
            id: sections
            model: ["connected", "paired", "nearby"]
            ScrollList {
                id: section
                required property string modelData
                readonly property var list: modelData === "connected" ? root.connected
                    : modelData === "paired" ? root.paired : root.nearby
                Layout.fillWidth: true
                title: modelData
                maxHeight: Metrics.rowHeight * 2
                Component.onCompleted: root.sectionsBuilt += 1
                Repeater {
                    model: ScriptModel { values: section.list }
                    ListRow {
                        id: row
                        required property var modelData
                        property alias remove: removeButton
                        width: parent.width
                        title: modelData.name
                        Component.onCompleted: { root.rowsBuilt += 1; root.rows[modelData.name] = row }
                        ShellButton { id: removeButton; icon: Icons.remove; compact: true; confirm: true; confirmText: "Remove" }
                    }
                }
            }
        }
        ScrollList {
            Layout.fillWidth: true
            title: "Applications"
            Repeater {
                model: ScriptModel { values: root.nodes }
                RowLayout {
                    id: stream
                    required property var modelData
                    property alias slider: volume
                    width: parent.width
                    Component.onCompleted: { root.streamsBuilt += 1; root.streams[modelData.name] = stream }
                    ShellSlider { id: volume; Layout.fillWidth: true; accessibleName: "Volume" }
                }
            }
        }
    }

    function device(name, paired) { return deviceType.createObject(root, { name: name, paired: paired }) }

    property int step: 0
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                root.devices = [root.device("Headphones", true), root.device("Mouse", true)]
                    .concat([1, 2, 3, 4].map(n => root.device("Speaker " + n, false)))
                root.nodes = [root.device("Browser", false), root.device("Player", false)]
                break
            case 1: {
                T.eq([root.sectionsBuilt, root.rowsBuilt, root.streamsBuilt], [3, 6, 2], "three sections, six devices, two streams")
                const button = root.rows["Headphones"].remove
                button.activate()
                T.ok(button.armed, "the first click arms Remove")
                const nearbyList = sections.itemAt(2).view
                nearbyList.contentY = Metrics.rowHeight
                root.armedButton = button
                root.slider = root.streams["Browser"].slider
                // Discovery finds a device, and an app starts playing.
                root.devices = root.devices.concat([root.device("Neighbour's speaker", false)])
                root.nodes = root.nodes.concat([root.device("Notification", false)])
                break
            }
            case 2:
                T.eq(root.sectionsBuilt, 3, "no section was built again")
                T.eq(root.rowsBuilt, 7, "only the new device's row was built")
                T.ok(root.rows["Headphones"].remove === root.armedButton, "the paired row is the same row")
                T.ok(root.armedButton.armed, "and its Remove is still armed for the second click")
                T.eq(sections.itemAt(2).view.contentY, Metrics.rowHeight, "the Nearby list stays where it was scrolled")
                T.eq(root.streamsBuilt, 3, "only the new stream's row was built")
                T.ok(root.streams["Browser"].slider === root.slider, "the slider under the hand is the same slider")
                // A device that connects moves between sections: its row is
                // made in the new one and the others stay.
                root.rows["Mouse"].modelData.connected = true
                root.devices = root.devices.slice()
                break
            case 3:
                T.eq(root.rowsBuilt, 8, "a device that moves section is one row, made where it went")
                T.ok(root.armedButton.armed, "and the armed Remove beside it is untouched")
                stop()
                T.finish("BluetoothListTest")
                break
            }
        }
    }
    property var armedButton: null
    property var slider: null
}
