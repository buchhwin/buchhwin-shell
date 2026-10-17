import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.popups

ColumnLayout {
    id: root
    spacing: Metrics.pageGap
    Component.onCompleted: NetworkService.setScanning(true)
    Component.onDestruction: NetworkService.setScanning(false)

    // Wi-Fi that can find networks: the radio flag on and an adapter to
    // search with. NetworkManager keeps the flag on where there is no adapter
    // at all, and the page searched forever beside nothing to search with.
    // (NetworkService.wifiUsable)
    readonly property bool wifiUsable: NetworkService.wifiUsable

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: header.implicitHeight + Metrics.spaceLg * 2
        RowLayout {
            id: header
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceMd
            // The Wi-Fi card's glyph is Wi-Fi's, as on the control center's
            // tile: the wire is named in the line below, not drawn here.
            // In a box of one width on the Wi-Fi, Bluetooth and Power pages:
            // sized by each glyph, the title beside it started at another x
            // on each page and jumped sideways on every switch.
            ShellIcon {
                Layout.preferredWidth: Metrics.iconXl
                glyph: NetworkService.wifiIcon
                size: Metrics.iconLg
                color: NetworkService.current ? Colors.accentForeground : Colors.mutedText
            }
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
                accessibleName: "Wi-Fi"
                checked: NetworkService.wifiEnabled
                enabledState: NetworkService.wifiAvailable
                onToggled: value => NetworkService.setWifiEnabled(value)
            }
        }
    }

    // The title inside the card and the popup's list height, as on the
    // Bluetooth page and in the network popup.
    ScrollList {
        Layout.fillWidth: true
        visible: root.wifiUsable
        title: "Networks"
        maxHeight: Metrics.popupListHeight
        EmptyState {
            visible: NetworkService.networks.length === 0
            x: Metrics.spaceLg
            width: parent.width - Metrics.spaceLg * 2
            row: true
            icon: Icons.busy
            title: "Searching for networks …"
        }
        Repeater {
            // Kept rows, not rebuilt ones; see NetworkPopup.
            model: ScriptModel { values: NetworkService.networks }
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
                ShellIcon { visible: !NetworkService.isOpen(modelData); glyph: Icons.lock; size: Metrics.iconXs; color: Colors.mutedText }
            }
        }
    }

    // The flag on and nothing to search with says so, as the network popup
    // does, rather than "Searching for networks …" for good.
    CardSection {
        Layout.fillWidth: true
        visible: NetworkService.wifiEnabled && !NetworkService.wifiAvailable
        EmptyState {
            Layout.fillWidth: true
            row: true
            icon: "󰤮"
            title: "No Wi-Fi adapter available"
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.wifiUsable
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

    // The tunnels in a titled card like the networks above them, and the
    // same list the network popup shows: a label over bare rows read as a
    // different kind of list from the card beside it.
    VpnList { Layout.fillWidth: true }

    ShellButton {
        icon: Icons.settings; compact: true; variant: "ghost"
        text: NetworkService.vpns.length ? "Edit VPN and connections" : "Set up VPN"
        onClicked: NetworkService.openSystemDialog()
    }
}
