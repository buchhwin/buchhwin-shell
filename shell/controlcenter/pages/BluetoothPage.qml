import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    id: root
    spacing: Metrics.panelGap
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
            ShellIcon { glyph: BluetoothService.icon; size: Metrics.iconLg; color: BluetoothService.enabled ? Colors.accentForeground : Colors.mutedText }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: "Bluetooth"; role: "bodyLarge" }
                ShellText { text: BluetoothService.discovering ? "Searching for devices …" : BluetoothService.summary; role: "small"; muted: true }
            }
            ShellToggle {
                checked: BluetoothService.enabled
                enabledState: BluetoothService.available
                onToggled: value => BluetoothService.setEnabled(value)
            }
        }
    }

    Repeater {
        model: [
            { label: "Connected", list: BluetoothService.connected },
            { label: "Paired", list: BluetoothService.paired },
            { label: "Nearby", list: BluetoothService.nearby }
        ]
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            visible: BluetoothService.enabled && modelData.list.length > 0
            spacing: Metrics.spaceXxs
            SectionLabel { text: modelData.label; Layout.leftMargin: Metrics.spaceSm }
            ScrollList {
                Layout.fillWidth: true
                maxHeight: 200
                Repeater {
                    model: modelData.list
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
                            confirmText: "Remove"
                            toolTip: "Remove device"
                            onClicked: BluetoothService.forget(modelData)
                        }
                    }
                }
            }
        }
    }

    ShellText {
        Layout.fillWidth: true
        visible: BluetoothService.enabled && BluetoothService.agentAllowed && !BluetoothService.agentReady
        text: "Pairing service is starting … Devices that need a confirmation code can be paired in a moment."
        role: "caption"
        wrapMode: Text.Wrap
        Layout.leftMargin: Metrics.spaceSm
    }
}
