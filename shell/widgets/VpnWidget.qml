import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services
WidgetBase {
    id: root
    // One glyph for both states; the colour says whether a tunnel is up.
    icon: "󰖂"
    iconColor: NetworkService.activeVpns.length ? Colors.success : root.mutedTextColor
    label: inGroup ? "" : (NetworkService.activeVpns.length ? NetworkService.activeVpns[0].name
        : NetworkService.vpns.length ? "VPN off" : "No VPN")
    maxLabelWidth: 140
    name: "VPN"
    // A second tunnel is invisible in the label, which only names the first.
    detail: NetworkService.activeVpns.length > 1
        ? NetworkService.activeVpns.length + " tunnels" : ""
}
