import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    id: root
    spacing: Metrics.pageGap
    Component.onCompleted: BluetoothService.setDiscovering(true)
    Component.onDestruction: BluetoothService.setDiscovering(false)

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + Metrics.spaceLg * 2
        RowLayout {
            id: header
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd
            // The Wi-Fi page's box (NetworkPage), so the title stays put.
            ShellIcon {
                Layout.preferredWidth: Metrics.iconXl
                glyph: BluetoothService.icon; size: Metrics.iconLg
                color: BluetoothService.enabled ? Colors.accentForeground : Colors.mutedText
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: "Bluetooth"; role: "bodyLarge" }
                // Filling like the Wi-Fi page's line. With no child that fills,
                // this column could not grow, the row spread its spare width
                // between its items, and the switch stood in the middle of
                // the card rather than at its edge, where Wi-Fi's stands.
                ShellText {
                    Layout.fillWidth: true
                    text: BluetoothService.discovering ? "Searching for devices …" : BluetoothService.summary
                    role: "small"; muted: true
                }
            }
            ShellToggle {
                accessibleName: "Bluetooth"
                checked: BluetoothService.enabled
                enabledState: BluetoothService.available
                onToggled: value => BluetoothService.setEnabled(value)
            }
        }
    }

    Repeater {
        // The sections by name, built once, and the rows kept by device
        // (ScriptModel; BlueZ's device objects keep their identity). Built
        // from a list of new objects, every section and row was made again
        // whenever discovery found a device: an armed Remove fell back to
        // its first click, the focus went, the Nearby list jumped to the top.
        model: ["connected", "paired", "nearby"]
        // The title inside the card, as the popup has it (ScrollList: a label
        // above a card reads as two things), and the popup's height for the
        // same lists.
        ScrollList {
            id: section
            required property string modelData
            readonly property var list: modelData === "connected" ? BluetoothService.connected
                : modelData === "paired" ? BluetoothService.paired : BluetoothService.nearby
            // Nearby stays while it is empty and says it is looking: with
            // every section gone the page said nothing at all about a scan
            // it had started.
            readonly property bool always: modelData === "nearby"
            Layout.fillWidth: true
            visible: BluetoothService.enabled && (list.length > 0 || always)
            title: modelData === "connected" ? "Connected" : modelData === "paired" ? "Paired" : "Nearby"
            maxHeight: Metrics.popupListHeight / 2 + Metrics.rowHeight
            EmptyState {
                visible: section.list.length === 0
                // Inset like the rows (ListRow's spaceLg), so its icon lines
                // up with theirs instead of sitting at the card's padding.
                x: Metrics.spaceLg
                width: parent.width - Metrics.spaceLg * 2
                row: true
                icon: BluetoothService.discovering ? Icons.busy : "󰂯"
                title: BluetoothService.discovering ? "Searching …" : "No devices found"
            }
            Repeater {
                model: ScriptModel { values: section.list }
                ListRow {
                    level: 1
                    required property var modelData
                    width: parent.width
                    icon: BluetoothService.deviceIcon(modelData)
                    title: modelData.name || modelData.address
                    subtitle: BluetoothService.deviceStatus(modelData)
                    active: modelData.connected
                    onClicked: BluetoothService.toggleConnection(modelData)
                    ShellButton {
                        visible: modelData.paired || modelData.bonded
                        icon: Icons.remove; variant: "ghost"; compact: true
                        // The pairing is gone for good, as in Settings.
                        confirm: true
                        confirmText: "Remove?"
                        toolTip: "Remove device"
                        onClicked: BluetoothService.forget(modelData)
                    }
                }
            }
        }
    }

    ShellText {
        Layout.fillWidth: true
        visible: BluetoothService.agentStarting
        text: "Pairing service is starting … Devices that need a confirmation code can be paired in a moment."
        role: "caption"
        wrapMode: Text.Wrap
        Layout.leftMargin: Metrics.spaceSm
    }
}
