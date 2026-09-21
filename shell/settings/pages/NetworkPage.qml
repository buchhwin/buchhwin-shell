import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Network: Wi-Fi networks, hotspot, VPN and connection details.
// Dialogs opened here return to this page.
ColumnLayout {
    id: root
    spacing: Metrics.spaceLg

    readonly property var back: ({ page: "network" })

    Component.onCompleted: NetworkService.setScanning(true)
    Component.onDestruction: NetworkService.setScanning(false)

    SettingsSection {
        Layout.fillWidth: true
        title: "Wi-Fi"
        description: NetworkService.summary + (NetworkService.address.length ? " · IP " + NetworkService.address : "")

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use Wi-Fi"
            ShellToggle {
                checked: NetworkService.wifiEnabled
                enabledState: NetworkService.wifiAvailable
                onToggled: value => NetworkService.setWifiEnabled(value)
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: !NetworkService.wifiAvailable
            text: "No Wi-Fi adapter found, or Wi-Fi is switched off by a hardware switch."
            role: "small"; color: Colors.warning; wrapMode: Text.Wrap
        }
        ShellText {
            Layout.fillWidth: true
            visible: NetworkService.helperError.length > 0
            text: NetworkService.helperError
            role: "small"; color: Colors.warning; wrapMode: Text.Wrap
        }
        ShellText {
            visible: NetworkService.wifiEnabled && NetworkService.networks.length === 0
            text: "Searching for networks …"
            muted: true
        }

        Repeater {
            model: NetworkService.wifiEnabled ? NetworkService.networks : []
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: NetworkService.signalIcon(modelData.signalStrength)
                title: modelData.name
                active: modelData.connected
                subtitle: modelData.stateChanging ? "Connecting …"
                    : (modelData.connected ? "Connected" : modelData.known ? "Saved" : "Not connected")
                      + " · " + (NetworkService.isOpen(modelData) ? "Open" : NetworkService.securityLabel(modelData))
                      + " · " + Math.round(modelData.signalStrength * 100) + "%"
                onClicked: NetworkService.activate(modelData, root.back)
                Row {
                    spacing: Metrics.spaceSm
                    ShellButton {
                        visible: modelData.known
                        icon: Icons.remove
                        compact: true
                        variant: "ghost"
                        // The saved password goes with it and nothing can bring
                        // it back, so it takes two clicks.
                        confirm: true
                        confirmText: "Forget"
                        toolTip: "Forget network"
                        onClicked: NetworkService.forget(modelData)
                    }
                    ShellButton {
                        text: modelData.connected ? "Disconnect" : "Connect"
                        compact: true
                        variant: modelData.connected ? "surface" : "accent"
                        onClicked: NetworkService.activate(modelData, root.back)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: NetworkService.wifiEnabled
            spacing: Metrics.spaceSm
            ShellButton {
                icon: "󰖩"
                text: "Hidden network …"
                compact: true
                onClicked: PanelService.openOver("wifiPassword", { ssid: "", hidden: true }, root.back)
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                icon: Icons.settings
                text: "Advanced …"
                compact: true
                variant: "ghost"
                onClicked: NetworkService.openSystemDialog()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Hotspot"
        description: "Share this computer's internet connection over Wi-Fi. Wi-Fi disconnects from its current network while the hotspot is on."

        RowLayout {
            ShellIcon { glyph: "󰀂"; size: Metrics.iconMd; color: NetworkService.hotspotActive ? Colors.accentForeground : Colors.mutedText }
            ShellText { Layout.fillWidth: true; text: NetworkService.hotspotActive ? "Hotspot is on" : "Hotspot is off" }
            ShellButton {
                text: NetworkService.hotspotActive ? "Stop hotspot" : "Start hotspot …"
                compact: true
                variant: NetworkService.hotspotActive ? "accent" : "surface"
                enabledState: NetworkService.wifiAvailable && NetworkService.helperState.length === 0
                onClicked: NetworkService.hotspotActive ? NetworkService.stopHotspot()
                    : PanelService.openOver("wifiPassword", { hotspot: true }, root.back)
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "VPN"
        description: "Turn VPN connections on or off. New VPNs are set up in KDE's connection editor."

        EmptyState { Layout.fillWidth: true; visible: NetworkService.vpns.length === 0; icon: "󰖂"; title: "No VPN connections set up" }
        Repeater {
            model: NetworkService.vpns
            ListRow {
                required property var modelData
                Layout.fillWidth: true
                icon: "󰖂"
                title: modelData.name
                subtitle: (modelData.active ? "Connected" : "Off") + " · " + (modelData.type === "wireguard" ? "WireGuard" : "VPN")
                active: modelData.active
                onClicked: NetworkService.setVpn(modelData.uuid, !modelData.active)
                ShellToggle { checked: modelData.active; onToggled: value => NetworkService.setVpn(modelData.uuid, value) }
            }
        }
        RowLayout {
            ShellButton {
                icon: Icons.settings
                text: NetworkService.vpns.length ? "Edit connections …" : "Set up VPN …"
                compact: true
                onClicked: NetworkService.openSystemDialog()
            }
        }
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Details"

        SettingRow {
            label: "Status"
            ShellText { Layout.fillWidth: true; text: NetworkService.summary; muted: true }
        }
        SettingRow {
            label: "Wi-Fi network"
            ShellText { Layout.fillWidth: true; text: NetworkService.current ? NetworkService.current.name : "–"; muted: true }
        }
        SettingRow {
            label: "Ethernet"
            ShellText { Layout.fillWidth: true; text: NetworkService.wiredConnected ? "Connected" : "Not connected"; muted: true }
        }
        SettingRow {
            label: "IP address"
            ShellText { Layout.fillWidth: true; text: NetworkService.address.length ? NetworkService.address : "–"; muted: true }
        }
        SettingRow {
            label: "Active VPN"
            ShellText { Layout.fillWidth: true; text: NetworkService.activeVpns.length ? NetworkService.activeVpns.map(item => item.name).join(", ") : "–"; muted: true }
        }
    }
}
