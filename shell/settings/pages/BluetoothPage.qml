import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Bluetooth: adapter, visibility, known and nearby devices. The
// pairing dialog opened while this page is shown returns here.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

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
            : (root.adapter && root.adapter.name || "Bluetooth adapter") + " · " + BluetoothService.summary

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
        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Low battery warning"
            hint: "A notification when a connected device - headphones, a mouse, a keyboard - is down to 15%, and again at 5%"
            ShellToggle {
                focusOnTab: true
                checked: SettingsService.value("bluetooth.batteryWarning") !== false
                onToggled: value => SettingsService.set("bluetooth.batteryWarning", value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: BluetoothService.agentStarting
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

        EmptyState { Layout.fillWidth: true; visible: root.known.length === 0; row: true; icon: "󰂯"; title: "No paired devices" }
        Repeater {
            // Kept rows (ScriptModel; BlueZ's device objects keep their
            // identity): `known` and `nearby` are new lists whenever
            // discovery finds a device or one connects, and every row was
            // built again - the keyboard focus and an armed Remove went.
            model: ScriptModel { values: root.known }
            // Not a tab stop of its own: its button does what a click on the
            // row does, and a stop for both made two or three per device.
            ListRow {
                level: 1
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
                        confirmText: "Remove?"
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
            row: true
            icon: BluetoothService.discovering ? Icons.busy : "󰂯"
            title: BluetoothService.discovering ? "Searching …" : "No devices found"
        }
        Repeater {
            model: ScriptModel { values: BluetoothService.nearby }
            // Not a tab stop of its own: its button does what a click on the
            // row does, and a stop for both made two or three per device.
            ListRow {
                level: 1
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
                // Stopping is no refresh: it wears the glyph that closes.
                icon: BluetoothService.discovering ? Icons.close : Icons.refresh
                text: BluetoothService.discovering ? "Stop searching" : "Search again"
                compact: true
                onClicked: BluetoothService.setDiscovering(!BluetoothService.discovering)
            }
        }
    }
}
