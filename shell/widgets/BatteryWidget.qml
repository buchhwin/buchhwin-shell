import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// Battery level, and from `medium` up what that level actually means: a bar,
// and how long it is good for. It used to be its own copy of WidgetBase's
// icon-and-label row, which is why it never gained anything the others did.
WidgetBase {
    id: root
    icon: PowerService.icon
    iconColor: PowerService.charging ? Colors.success
        : PowerService.percent <= 15 && PowerService.onBattery ? Colors.danger : root.textColor
    label: PowerService.percent + "%"
    name: PowerService.hasBattery ? "Battery" : "Power"
    meter: PowerService.hasBattery ? PowerService.percent / 100 : -1
    meterColor: PowerService.charging ? Colors.success
        : PowerService.percent <= 15 ? Colors.danger : Colors.accent
    detail: PowerService.remainingLabel.length ? PowerService.remainingLabel : PowerService.stateLabel
}
