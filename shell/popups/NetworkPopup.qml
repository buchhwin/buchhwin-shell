import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// Network pill/widget: Wi-Fi switch, current connection and address, nearby
// networks and VPNs. Scans only while open; the password dialog returns here.
PopupPanel {
    id: root
    panelId: "networkPopup"
    heading: "Wi-Fi"
    detail: NetworkService.summary + (NetworkService.connected && NetworkService.address.length ? " · " + NetworkService.address : "")
    glyph: NetworkService.icon
    glyphActive: NetworkService.connected
    hasToggle: true
    toggleChecked: NetworkService.wifiEnabled
    toggleEnabled: NetworkService.wifiAvailable
    onToggled: checked => NetworkService.setWifiEnabled(checked)
    footerText: "Network settings"
    onFooterClicked: PanelService.open("settings", { page: "network" })
    onWantedChanged: if (wanted) NetworkService.refresh()

    body: ColumnLayout {
        spacing: Metrics.panelGap
        Component.onCompleted: NetworkService.setScanning(true)
        Component.onDestruction: NetworkService.setScanning(false)

        CardSection {
            Layout.fillWidth: true
            visible: NetworkService.wiredConnected
            padding: Metrics.spaceSm
            ListRow {
                Layout.fillWidth: true
                level: 1
                icon: "󰈀"
                title: "Ethernet"
                subtitle: "Connected"
                active: true
            }
        }

        CardSection {
            Layout.fillWidth: true
            visible: !NetworkService.wifiEnabled
            EmptyState {
                Layout.fillWidth: true
                icon: "󰤮"
                title: NetworkService.wifiAvailable ? "Wi-Fi is turned off" : "No Wi-Fi adapter available"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: NetworkService.wifiEnabled
            spacing: Metrics.spaceXxs
            ScrollList {
                Layout.fillWidth: true
                title: "Networks"
                maxHeight: Metrics.popupListHeight
                EmptyState {
                    visible: NetworkService.networks.length === 0
                    width: parent.width
                    row: true
                    icon: Icons.busy
                    title: "Searching for networks …"
                }
                Repeater {
                    model: NetworkService.networks
                    ListRow {
                        focusOnTab: true
                        level: 1
                        required property var modelData
                        width: parent.width
                        icon: NetworkService.signalIcon(modelData.signalStrength)
                        title: modelData.name
                        active: modelData.connected
                        subtitle: modelData.stateChanging ? "Connecting …"
                            : modelData.connected ? "Connected"
                            : modelData.known ? "Saved"
                            : NetworkService.securityLabel(modelData)
                        // Without returnArgs the dialog reopens this popup at the same place.
                        onClicked: NetworkService.activate(modelData)
                        ShellIcon { visible: !NetworkService.isOpen(modelData); glyph: "󰌾"; size: Metrics.iconXs; color: Colors.mutedText }
                    }
                }
            }
        }

        VpnList { Layout.fillWidth: true; visible: NetworkService.vpns.length > 0 }
    }
}
