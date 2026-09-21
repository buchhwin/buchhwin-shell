import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// VPN pill/widget: every VPN connection with its switch.
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
    onWantedChanged: if (wanted) NetworkService.refresh()

    body: ColumnLayout {
        spacing: Metrics.panelGap

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

        ShellButton {
            icon: Icons.settings; compact: true; variant: "ghost"
            text: NetworkService.vpns.length ? "Edit VPN connections" : "Set up VPN"
            onClicked: NetworkService.openSystemDialog()
        }
    }
}
