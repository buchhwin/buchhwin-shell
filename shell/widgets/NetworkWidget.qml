import QtQuick
import qs.shell.widgets
import qs.services
WidgetBase {
    icon: NetworkService.icon
    label: inGroup ? "" : NetworkService.summary
    maxLabelWidth: 160
    name: "Network"
}
