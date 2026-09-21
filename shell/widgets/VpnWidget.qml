import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
WidgetBase {
    id: root
    icon: NetworkService.activeVpns.length ? "󰖂" : "󰖂"
    iconColor: NetworkService.activeVpns.length ? Colors.success : root.mutedTextColor
    label: inGroup ? "" : (NetworkService.activeVpns.length ? NetworkService.activeVpns[0].name : "VPN off")
    maxLabelWidth: 140
    name: "VPN"
    // A second tunnel is invisible in the label, which only names the first.
    detail: NetworkService.activeVpns.length > 1
        ? NetworkService.activeVpns.length + " tunnels" : ""
}
