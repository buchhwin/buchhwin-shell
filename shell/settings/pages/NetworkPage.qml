import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Settings > Network: Wi-Fi networks, hotspot, VPN and connection details.
// Dialogs opened here return to this page.
ColumnLayout {
    id: root
    spacing: Metrics.pageGap

    readonly property var back: ({ page: "network" })

    PageActivity {
        onOpened: NetworkService.setScanning(true)
        onClosed: NetworkService.setScanning(false)
    }

    SettingsSection {
        Layout.fillWidth: true
        title: "Wi-Fi"
        description: NetworkService.summary + (NetworkService.address.length ? " · IP " + NetworkService.address : "")

        SettingRow {
            Layout.fillWidth: true
            labelFills: true
            label: "Use Wi-Fi"
            ShellToggle {
                focusOnTab: true
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
        EmptyState {
            Layout.fillWidth: true
            visible: NetworkService.wifiEnabled && NetworkService.networks.length === 0
            row: true
            icon: Icons.busy
            title: "Searching for networks …"
        }

        Repeater {
            // Kept rows, not rebuilt ones; see NetworkPopup.
            model: ScriptModel { values: NetworkService.wifiEnabled ? NetworkService.networks : [] }
            ListRow {
                focusOnTab: true
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
                        focusOnTab: true
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
                        focusOnTab: true
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
                focusOnTab: true
                icon: "󰖩"
                text: "Hidden network …"
                compact: true
                onClicked: PanelService.openOver("wifiPassword", { ssid: "", hidden: true }, root.back)
            }
            Item { Layout.fillWidth: true }
            ShellButton {
                focusOnTab: true
                icon: Icons.settings
                text: "Edit VPN and connections"
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
                focusOnTab: true
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
        description: "Turn VPN connections on or off, and add WireGuard tunnels. They are NetworkManager's, so Plasma lists the same ones."

        EmptyState { Layout.fillWidth: true; visible: NetworkService.vpns.length === 0; icon: "󰖂"; title: "No VPN connections set up yet" }
        Repeater {
            model: NetworkService.vpns
            ListRow {
                focusOnTab: true
                required property var modelData
                Layout.fillWidth: true
                icon: "󰖂"
                title: modelData.name
                subtitle: (modelData.active ? "Connected" : "Off") + " · " + (modelData.type === "wireguard" ? "WireGuard" : "VPN")
                active: modelData.active
                onClicked: NetworkService.setVpn(modelData.uuid, !modelData.active)
                // One item in the row's trailing slot, as the Wi-Fi rows have:
                // the slot is a plain Item, and two children of it both sat
                // at its origin, the switch on top of the delete button.
                Row {
                    spacing: Metrics.spaceSm
                    // A tunnel goes for good, so the button asks twice.
                    ShellButton {
                        focusOnTab: true
                        visible: modelData.type === "wireguard"
                        compact: true
                        variant: "ghost"
                        icon: Icons.remove
                        toolTip: "Delete this tunnel"
                        confirm: true
                        confirmText: "Delete"
                        onClicked: NetworkService.wgDelete(modelData.uuid)
                    }
                    ShellToggle {
                        focusOnTab: true
                        anchors.verticalCenter: parent.verticalCenter
                        accessibleName: modelData.name
                        checked: modelData.active
                        onToggled: value => NetworkService.setVpn(modelData.uuid, value)
                    }
                }
            }
        }
        ShellText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: NetworkService.wgError.length ? NetworkService.wgError : NetworkService.wgNotice
            color: NetworkService.wgError.length ? Colors.danger : Colors.mutedText
            role: "small"
            wrapMode: Text.Wrap
        }
        Loader {
            id: wireguardForm
            Layout.fillWidth: true
            active: false
            visible: active
            sourceComponent: WireguardForm { onDone: wireguardForm.active = false }
        }
        RowLayout {
            spacing: Metrics.spaceSm
            ShellButton {
                focusOnTab: true
                icon: Icons.add
                text: "New WireGuard tunnel"
                compact: true
                visible: !wireguardForm.active
                onClicked: { NetworkService.wgNotice = ""; NetworkService.wgError = ""; wireguardForm.active = true }
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.folder
                text: "Import file …"
                compact: true
                onClicked: NetworkService.wgImport()
            }
            ShellButton {
                focusOnTab: true
                icon: Icons.settings
                text: "Edit VPN and connections"
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
