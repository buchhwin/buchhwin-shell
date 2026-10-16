import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.shell.components

ColumnLayout {
    spacing: Metrics.pageGap

    ShellCard {
        Layout.fillWidth: true
        implicitHeight: batteryColumn.implicitHeight + Metrics.spaceLg * 2
        ColumnLayout {
            id: batteryColumn
            anchors.fill: parent
            anchors.margins: Metrics.spaceLg
            spacing: Metrics.spaceSm
            // The glyph shows a state only when there is one: charging, or low
            // (PowerService's level, the one the warning uses). Otherwise it is
            // the page's ink, as the bar widget's is. The accent on the
            // Network and Bluetooth pages says "on", and running on battery is
            // not something switched on - in the accent it read as a setting.
            // Charging is on: the green, or the accent when Settings > Power >
            // Status colors asks for it.
            RowLayout {
                spacing: Metrics.spaceMd
                // The Wi-Fi page's box (NetworkPage), so the figure beside
                // it starts where the Wi-Fi and Bluetooth titles do.
                ShellIcon {
                    Layout.preferredWidth: Metrics.iconXl
                    glyph: PowerService.icon; size: Metrics.iconXl
                    color: PowerService.charging ? Colors.positive : PowerService.low ? Colors.danger : Colors.text
                }
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

    // The title inside the card, as on every other page of the control center
    // (Audio's "Output", the Network and Bluetooth lists): an upper-case
    // label floating above a bare control was the one section here drawn
    // another way.
    CardSection {
        Layout.fillWidth: true
        title: "Power profile"
        SegmentedControl {
            Layout.fillWidth: true
            accessibleName: "Power profile"
            current: String(PowerService.profile)
            options: [
                { value: String(PowerProfile.PowerSaver), label: "Power saver", icon: "󰌪" },
                { value: String(PowerProfile.Balanced), label: "Balanced", icon: "󰾅" }
            ].concat(PowerService.hasPerformance ? [{ value: String(PowerProfile.Performance), label: "Performance", icon: "󰓅" }] : [])
            onSelected: value => PowerService.setProfile(parseInt(value))
        }
    }
    ShellText {
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.spaceSm
        text: "Screen off, lock and sleep timeouts and what happens when the lid closes are in the power settings."
        role: "caption"
        wrapMode: Text.Wrap
    }
    // A way there rather than a path to type into a search: the same button
    // the drives page has for its settings.
    ShellButton {
        icon: Icons.settings; text: "Power settings"; variant: "ghost"; compact: true
        onClicked: PanelService.open("settings", { page: "power" })
    }
}
