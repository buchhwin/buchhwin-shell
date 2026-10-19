import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.network

// VPN pill/widget: every VPN connection with its switch, and the network
// drives that need one (NetworkShares: from mountinfo alone, never touched
// while no VPN is up).
PopupPanel {
    id: root
    panelId: "vpnPopup"
    heading: "VPN"
    detail: NetworkService.activeVpns.length === 1 ? "Connected to " + NetworkService.activeVpns[0].name
        : NetworkService.activeVpns.length > 1 ? NetworkService.activeVpns.length + " connections active"
        : NetworkService.vpns.length ? "Not connected" : "Not set up"
    glyph: "󰖂"
    glyphActive: NetworkService.activeVpns.length > 0
    footerText: "Network settings"
    onFooterClicked: PanelService.open("settings", { page: "network" })
    // Only when NetworkManager said something since the last read (see
    // NetworkPopup).
    onWantedChanged: if (wanted) NetworkService.refreshIfStale()

    body: ColumnLayout {
        spacing: Metrics.pageGap

        VpnList { Layout.fillWidth: true; showLabel: false }

        CardSection {
            Layout.fillWidth: true
            visible: NetworkService.vpns.length === 0
            EmptyState {
                Layout.fillWidth: true
                icon: "󰖂"
                title: "No VPN connections set up yet"
            }
        }

        NetworkShares { Layout.fillWidth: true }

        ShellButton {
            focusOnTab: true
            icon: Icons.settings; compact: true; variant: "ghost"
            text: "Edit VPN and connections"
            onClicked: NetworkService.openSystemDialog()
        }
    }
}
