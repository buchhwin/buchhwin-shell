import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Bluetooth pill/widget: adapter switch, connected and paired devices with
// connect/disconnect and battery, nearby devices with Pair. Discovery runs
// only while the popup is open.
PopupPanel {
    id: root
    panelId: "bluetoothPopup"
    heading: "Bluetooth"
    detail: BluetoothService.enabled && BluetoothService.discovering && BluetoothService.connected.length === 0
        ? "Searching for devices …" : BluetoothService.summary
    glyph: BluetoothService.icon
    glyphActive: BluetoothService.enabled
    hasToggle: true
    toggleChecked: BluetoothService.enabled
    toggleEnabled: BluetoothService.available
    onToggled: checked => BluetoothService.setEnabled(checked)
    footerText: "Bluetooth settings"
    onFooterClicked: PanelService.open("settings", { page: "bluetooth" })

    body: ColumnLayout {
        id: content
        spacing: Metrics.pageGap
        // One viewer of the search, in a pair: BluetoothService counts them,
        // so Settings opened from the footer keeps searching after this body
        // is gone, and an adapter switched on while this is open starts
        // searching by itself.
        Component.onCompleted: BluetoothService.setDiscovering(true)
        Component.onDestruction: BluetoothService.setDiscovering(false)

        CardSection {
            Layout.fillWidth: true
            visible: !BluetoothService.enabled
            EmptyState {
                Layout.fillWidth: true
                icon: "󰂲"
                title: BluetoothService.available ? "Bluetooth is turned off" : "No Bluetooth adapter available"
            }
        }

        Repeater {
            // The sections by name, built once, and the rows kept by device
            // (ScriptModel; BlueZ's device objects keep their identity). Built
            // from a list of new objects, both lists and every row were made
            // again whenever discovery found a device: the Nearby list jumped
            // back to its top and a row lost its hover or focus mid-click.
            model: ["devices", "nearby"]
            ScrollList {
                id: section
                required property string modelData
                readonly property bool nearby: modelData === "nearby"
                readonly property var list: nearby ? BluetoothService.nearby
                    : BluetoothService.connected.concat(BluetoothService.paired)
                Layout.fillWidth: true
                // Nearby stays while it is empty and says it is looking.
                visible: BluetoothService.enabled && (list.length > 0 || nearby)
                title: nearby ? "Nearby" : "Devices"
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
                        focusOnTab: true
                        level: 1
                        required property var modelData
                        width: parent.width
                        icon: BluetoothService.deviceIcon(modelData)
                        title: modelData.name || modelData.address
                        subtitle: BluetoothService.deviceStatus(modelData)
                        active: modelData.connected
                        onClicked: BluetoothService.toggleConnection(modelData)
                        ShellButton {
                            focusOnTab: true
                            compact: true
                            variant: modelData.connected ? "ghost" : "surface"
                            enabledState: !modelData.pairing
                            text: modelData.connected ? "Disconnect" : modelData.paired || modelData.bonded ? "Connect" : "Pair"
                            onClicked: BluetoothService.toggleConnection(modelData)
                        }
                    }
                }
            }
        }

        ShellText {
            Layout.fillWidth: true
            Layout.leftMargin: Metrics.spaceSm
            visible: BluetoothService.agentStarting
            text: "Pairing service is starting … Devices that need a confirmation code can be paired in a moment."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
