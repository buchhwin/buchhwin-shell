import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    id: root
    spacing: Metrics.panelGap
    Component.onCompleted: NetworkService.setScanning(true)
    Component.onDestruction: NetworkService.setScanning(false)

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + Metrics.spaceLg * 2
        RowLayout {
            id: header
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd
            ShellIcon { glyph: NetworkService.icon; size: Metrics.iconLg; color: NetworkService.connected ? Colors.accentForeground : Colors.mutedText }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ShellText { text: "Wi-Fi"; role: "bodyLarge" }
                ShellText {
                    Layout.fillWidth: true
                    text: NetworkService.summary + (NetworkService.address.length ? " · " + NetworkService.address : "")
                    role: "small"; muted: true
                }
            }
            ShellToggle {
                checked: NetworkService.wifiEnabled
                enabledState: NetworkService.wifiAvailable
                onToggled: value => NetworkService.setWifiEnabled(value)
            }
        }
    }

    SectionLabel { text: "Networks"; visible: NetworkService.wifiEnabled; Layout.leftMargin: Metrics.spaceSm }

    ScrollList {
        Layout.fillWidth: true
        visible: NetworkService.wifiEnabled
        maxHeight: 300
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
                level: 1
                required property var modelData
                width: parent.width
                icon: NetworkService.signalIcon(modelData.signalStrength)
                title: modelData.name
                active: modelData.connected
                subtitle: modelData.stateChanging ? "Connecting …"
                    : modelData.connected ? "Connected"
                    : modelData.known ? "Saved"
                    : NetworkService.isOpen(modelData) ? "Open"
                    : NetworkService.securityLabel(modelData)
                onClicked: NetworkService.activate(modelData, { page: "network" })
                ShellIcon { visible: !NetworkService.isOpen(modelData); glyph: "󰌾"; size: Metrics.iconXs; color: Colors.mutedText }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: NetworkService.wifiEnabled
        spacing: Metrics.spaceSm
        ShellButton { icon: "󰖩"; text: "Hidden network"; compact: true; onClicked: PanelService.openOver("wifiPassword", { ssid: "", hidden: true }, { page: "network" }) }
        Item { Layout.fillWidth: true }
        ShellButton {
            icon: "󰀂"; compact: true
            text: NetworkService.hotspotActive ? "Stop hotspot" : "Hotspot"
            variant: NetworkService.hotspotActive ? "accent" : "surface"
            onClicked: NetworkService.hotspotActive ? NetworkService.stopHotspot() : PanelService.openOver("wifiPassword", { hotspot: true }, { page: "network" })
        }
    }

    SectionLabel { text: "VPN"; visible: NetworkService.vpns.length > 0; Layout.leftMargin: Metrics.spaceSm }
    Repeater {
        model: NetworkService.vpns
        ListRow {
            required property var modelData
            Layout.fillWidth: true
            icon: "󰖂"
            title: modelData.name
            subtitle: modelData.active ? "Connected" : "Off"
            active: modelData.active
            ShellToggle { checked: modelData.active; onToggled: value => NetworkService.setVpn(modelData.uuid, value) }
            onClicked: NetworkService.setVpn(modelData.uuid, !modelData.active)
        }
    }

    ShellButton {
        icon: Icons.settings; compact: true; variant: "ghost"
        text: NetworkService.vpns.length ? "Edit VPN and connections" : "Set up VPN"
        onClicked: NetworkService.openSystemDialog()
    }
}
