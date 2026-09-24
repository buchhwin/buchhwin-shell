import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Bluetooth: adapter, visibility, known and nearby devices. The
// pairing dialog opened while this page is shown returns here.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var adapter: BluetoothService.adapter
    readonly property var known: BluetoothService.connected.concat(BluetoothService.paired)

    PageActivity {
        onOpened: BluetoothService.setDiscovering(true)
        onClosed: BluetoothService.setDiscovering(false)
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Bluetooth"
        description: !BluetoothService.available ? "No Bluetooth adapter found"
            : (root.adapter.name || "Bluetooth adapter") + " · " + BluetoothService.summary

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use Bluetooth"
            ShellToggle {
                focusOnTab: true
                checked: BluetoothService.enabled
                enabledState: BluetoothService.available
                onToggled: value => BluetoothService.setEnabled(value)
            }
        }
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            visible: BluetoothService.enabled
            label: "Visible to other devices"
            hint: "Lets phones and computers find this device while it is on"
            ShellToggle {
                focusOnTab: true
                checked: root.adapter !== null && root.adapter.discoverable
                onToggled: value => BluetoothService.setDiscoverable(value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: BluetoothService.enabled && BluetoothService.agentAllowed && !BluetoothService.agentReady
            text: "Pairing service is starting … Devices that need a confirmation code can be paired in a moment."
            role: "caption"
            wrapMode: Text.Wrap
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: BluetoothService.enabled
        title: "My devices"
        description: "Paired devices. Connect, disconnect or remove them."

        EmptyState { Layout.fillWidth: true; visible: root.known.length === 0; icon: "󰂯"; title: "No paired devices" }
        Repeater {
            model: root.known
            ListRow {
                focusOnTab: true
                required property var modelData
                Layout.fillWidth: true
                icon: BluetoothService.deviceIcon(modelData)
                title: modelData.name || modelData.address
                subtitle: BluetoothService.deviceStatus(modelData) + " · " + modelData.address
                active: modelData.connected
                onClicked: BluetoothService.toggleConnection(modelData)
                Row {
                    spacing: Metrics.spaceSm
                    ShellButton {
                        focusOnTab: true
                        icon: Icons.remove
                        compact: true
                        variant: "ghost"
                        // The pairing is gone; the device has to be paired
                        // again from both ends.
                        confirm: true
                        confirmText: "Remove"
                        toolTip: "Remove device"
                        onClicked: BluetoothService.forget(modelData)
                    }
                    ShellButton {
                        focusOnTab: true
                        text: modelData.connected ? "Disconnect" : "Connect"
                        compact: true
                        variant: modelData.connected ? "surface" : "accent"
                        onClicked: BluetoothService.toggleConnection(modelData)
                    }
                }
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        visible: BluetoothService.enabled
        title: "Nearby devices"
        description: BluetoothService.discovering ? "Searching … Put the device you want to pair into pairing mode."
            : "Search to find devices that can be paired."

        EmptyState {
            Layout.fillWidth: true
            visible: BluetoothService.nearby.length === 0
            icon: BluetoothService.discovering ? Icons.busy : "󰂯"
            title: BluetoothService.discovering ? "Searching …" : "No devices found"
        }
        Repeater {
            model: BluetoothService.nearby
            ListRow {
                focusOnTab: true
                required property var modelData
                Layout.fillWidth: true
                icon: BluetoothService.deviceIcon(modelData)
                title: modelData.name || modelData.address
                subtitle: BluetoothService.deviceStatus(modelData) + " · " + modelData.address
                onClicked: BluetoothService.toggleConnection(modelData)
                ShellButton {
                    focusOnTab: true
                    text: modelData.pairing ? "Pairing …" : "Pair"
                    compact: true
                    variant: "accent"
                    enabledState: !modelData.pairing
                    onClicked: BluetoothService.toggleConnection(modelData)
                }
            }
        }
        RowLayout {
            ShellButton {
                focusOnTab: true
                icon: Icons.refresh
                text: BluetoothService.discovering ? "Stop searching" : "Search again"
                compact: true
                onClicked: BluetoothService.setDiscovering(!BluetoothService.discovering)
            }
        }
    }
}
