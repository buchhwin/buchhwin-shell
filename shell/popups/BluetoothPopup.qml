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
        spacing: Metrics.panelGap
        readonly property bool adapterOn: BluetoothService.enabled
        Component.onCompleted: BluetoothService.setDiscovering(true)
        Component.onDestruction: BluetoothService.setDiscovering(false)
        // Discovery starts only on a powered adapter; switching it on while open starts it too.
        onAdapterOnChanged: if (adapterOn) BluetoothService.setDiscovering(true)

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
            model: [
                { label: "Devices", list: BluetoothService.connected.concat(BluetoothService.paired), action: "" },
                { label: "Nearby", list: BluetoothService.nearby, action: "Pair" }
            ]
            ScrollList {
                id: section
                required property var modelData
                Layout.fillWidth: true
                visible: BluetoothService.enabled && (modelData.list.length > 0 || modelData.action.length > 0)
                title: section.modelData.label
                maxHeight: Metrics.popupListHeight / 2 + Metrics.rowHeight

                EmptyState {
                    visible: section.modelData.list.length === 0
                    width: parent.width
                    row: true
                    icon: BluetoothService.discovering ? Icons.busy : "󰂯"
                    title: BluetoothService.discovering ? "Searching …" : "No devices found"
                }
                Repeater {
                    model: section.modelData.list
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
            visible: BluetoothService.enabled && BluetoothService.agentAllowed && !BluetoothService.agentReady
            text: "Pairing service is starting …"
            role: "caption"
            wrapMode: Text.Wrap
        }
    }
}
