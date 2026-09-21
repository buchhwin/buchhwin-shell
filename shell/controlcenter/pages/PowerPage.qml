import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.panelGap

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: batteryColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: batteryColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceSm
            RowLayout {
                spacing: Metrics.spaceMd
                ShellIcon { glyph: PowerService.icon; size: Metrics.iconXl; color: PowerService.charging ? Colors.success : Colors.accentForeground }
                ColumnLayout {
                    spacing: 0
                    ShellText { text: PowerService.hasBattery ? PowerService.percent + "%" : "AC power"; role: "headline" }
                    ShellText { text: PowerService.stateLabel; role: "small"; muted: true }
                }
            }
            ShellText { visible: PowerService.remainingLabel.length > 0; text: PowerService.remainingLabel; muted: true }
            ShellText {
                visible: PowerService.device !== null && PowerService.device.healthPercentage > 0
                text: PowerService.device ? "Battery health " + Math.round(PowerService.device.healthPercentage) + "%" : ""
                role: "small"; muted: true
            }
        }
    }

    SectionLabel { text: "Power profile"; Layout.leftMargin: Metrics.spaceSm }
    SegmentedControl {
        Layout.fillWidth: true
        current: String(PowerService.profile)
        options: [
            { value: String(PowerProfile.PowerSaver), label: "Power saver", icon: "󰌪" },
            { value: String(PowerProfile.Balanced), label: "Balanced", icon: "󰾅" }
        ].concat(PowerService.hasPerformance ? [{ value: String(PowerProfile.Performance), label: "Performance", icon: "󰓅" }] : [])
        onSelected: value => PowerService.setProfile(parseInt(value))
    }
    ShellText {
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceSm
        text: "Screen off, lock and sleep timeouts and what happens when the lid closes are in Settings > Power."
        role: "caption"
        wrapMode: Text.Wrap
    }
}
