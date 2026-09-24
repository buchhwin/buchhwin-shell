import QtQuick
import qs.theme
import qs.services
import qs.shell.components

// VPN connections with a switch each (network and VPN popups). A card like
// every other group of rows; `showLabel: false` is for a popup that already
// says VPN in its header.
ScrollList {
    id: root
    property bool showLabel: true
    title: root.showLabel && NetworkService.vpns.length > 0 ? "VPN" : ""
    visible: NetworkService.vpns.length > 0

    Repeater {
        model: NetworkService.vpns
        ListRow {
            focusOnTab: true
            required property var modelData
            width: parent.width
            level: 1
            icon: "󰖂"
            title: modelData.name
            subtitle: modelData.active ? "Connected" : "Off"
            active: modelData.active
            onClicked: NetworkService.setVpn(modelData.uuid, !modelData.active)
            ShellToggle { focusOnTab: true; checked: modelData.active; onToggled: value => NetworkService.setVpn(modelData.uuid, value) }
        }
    }
}
