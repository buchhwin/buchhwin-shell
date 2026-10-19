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
    // VPN rows are keyed by the connection's uuid and read it here: turning
    // one on or off (or any Wi-Fi switch) gives NetworkService a new list,
    // and a Repeater on the list itself built every row again - the
    // keyboard lost the switch it had just pressed, and an armed Delete on
    // another tunnel was disarmed.
    readonly property var vpnByUuid: {
        const table = {}
        for (const item of NetworkService.vpns) table[item.uuid] = item
        return table
    }

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
            // Without an adapter it is off and cannot be turned on, rather
            // than on and grayed out beside "No Wi-Fi adapter found".
            ShellToggle {
                focusOnTab: true
                checked: NetworkService.wifiUsable
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
            visible: NetworkService.searching
            row: true
            icon: Icons.busy
            title: "Searching for networks …"
        }

        Repeater {
            // Kept rows, not rebuilt ones; see NetworkPopup.
            model: ScriptModel { values: NetworkService.wifiUsable ? NetworkService.networks : [] }
            // Not a tab stop of its own: its Connect button does what a click
            // on the row does, and a stop for both made two or three per
            // network on the way down the page.
            ListRow {
                level: 1
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
                        confirmText: "Forget?"
                        toolTip: "Forget network"
                        onClicked: NetworkService.forget(modelData)
                    }
                    // Plain, not the accent: with every network in range
                    // wearing one, the accent marked nothing, and the row
                    // connects on a click by itself.
                    ShellButton {
                        focusOnTab: true
                        text: modelData.connected ? "Disconnect" : "Connect"
                        compact: true
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
                visible: NetworkService.wifiUsable
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

        EmptyState { Layout.fillWidth: true; visible: NetworkService.vpns.length === 0; row: true; icon: "󰖂"; title: "No VPN connections set up yet" }
        Repeater {
            model: ScriptModel { values: NetworkService.vpns.map(item => item.uuid) }
            // Not a tab stop either: the switch in it is the same action.
            ListRow {
                id: vpnRow
                level: 1
                required property string modelData
                // Gone in the same turn as its row: an empty one until then.
                readonly property var vpn: root.vpnByUuid[modelData]
                    || ({ name: "", uuid: modelData, type: "", active: false, device: "" })
                Layout.fillWidth: true
                icon: "󰖂"
                title: vpnRow.vpn.name
                // "Connecting …" while a switch is under way (NetworkService.vpnPending).
                subtitle: NetworkService.vpnStatus(vpnRow.vpn) + " · " + (vpnRow.vpn.type === "wireguard" ? "WireGuard" : "VPN")
                active: vpnRow.vpn.active
                onClicked: NetworkService.setVpn(vpnRow.vpn.uuid, !NetworkService.vpnChecked(vpnRow.vpn))
                // One item in the row's trailing slot, as the Wi-Fi rows have:
                // the slot is a plain Item, and two children of it both sat
                // at its origin, the switch on top of the delete button.
                Row {
                    spacing: Metrics.spaceSm
                    // A tunnel goes for good, so the button asks twice.
                    ShellButton {
                        focusOnTab: true
                        visible: vpnRow.vpn.type === "wireguard"
                        compact: true
                        variant: "ghost"
                        icon: Icons.remove
                        toolTip: "Delete this tunnel"
                        confirm: true
                        confirmText: "Delete?"
                        onClicked: NetworkService.wgDelete(vpnRow.vpn.uuid)
                    }
                    ShellToggle {
                        focusOnTab: true
                        anchors.verticalCenter: parent.verticalCenter
                        accessibleName: vpnRow.vpn.name
                        checked: NetworkService.vpnChecked(vpnRow.vpn)
                        onToggled: value => NetworkService.setVpn(vpnRow.vpn.uuid, value)
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
            // A key generated and not yet used brings the form back with it
            // when the page is built again (NetworkService.wgPrivate).
            active: false
            Component.onCompleted: if (NetworkService.wgPrivate.length) active = true
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
