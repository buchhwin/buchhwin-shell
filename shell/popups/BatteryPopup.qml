import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.shell.components

// Battery pill/widget: charge, state, time remaining, health and the power
// profile.
PopupPanel {
    id: root
    panelId: "batteryPopup"
    heading: PowerService.hasBattery ? "Battery" : "Power"
    detail: PowerService.stateLabel
    glyph: PowerService.icon
    glyphActive: PowerService.charging || PowerService.full
    footerText: "Power settings"
    onFooterClicked: PanelService.open("settings", { page: "power" })

    body: ColumnLayout {
        spacing: Metrics.panelGap

        CardSection {
            Layout.fillWidth: true
            visible: PowerService.hasBattery
            spacing: Metrics.spaceSm

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                Text {
                    text: PowerService.percent + "%"
                    color: Colors.text
                    font.family: Typography.family
                    font.pixelSize: Typography.batteryPercentSize
                    font.weight: Typography.light
                    font.features: { "tnum": 1 }
                    renderType: Typography.renderType
                }
                Item { Layout.fillWidth: true }
                ShellText {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Metrics.spaceXs
                    text: PowerService.remainingLabel
                    visible: text.length > 0
                    role: "small"; muted: true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Metrics.meterHeight
                radius: height / 2
                color: Colors.track
                Rectangle {
                    width: parent.width * PowerService.percent / 100
                    height: parent.height
                    radius: parent.radius
                    color: PowerService.charging ? Colors.success
                        : PowerService.percent <= 15 ? Colors.danger : Colors.accent
                }
            }

            RowLayout {
                visible: PowerService.device !== null && PowerService.device.healthPercentage > 0
                Layout.fillWidth: true
                Layout.topMargin: Metrics.spaceXs
                ShellText { Layout.fillWidth: true; text: "Battery health"; role: "small"; muted: true }
                ShellText {
                    text: PowerService.device ? Math.round(PowerService.device.healthPercentage) + "%" : ""
                    role: "small"
                    font.features: { "tnum": 1 }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: PowerService.device !== null && PowerService.device.changeRate > 0
                ShellText { Layout.fillWidth: true; text: PowerService.charging ? "Charging rate" : "Power draw"; role: "small"; muted: true }
                ShellText {
                    text: PowerService.device ? PowerService.device.changeRate.toFixed(1) + " W" : ""
                    role: "small"
                    font.features: { "tnum": 1 }
                }
            }
        }

        CardSection {
            Layout.fillWidth: true
            title: "Power profile"
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                current: String(PowerService.profile)
                options: [
                    { value: String(PowerProfile.PowerSaver), label: "Power saver", icon: "󰌪" },
                    { value: String(PowerProfile.Balanced), label: "Balanced", icon: "󰾅" }
                ].concat(PowerService.hasPerformance ? [{ value: String(PowerProfile.Performance), label: "Performance", icon: "󰓅" }] : [])
                onSelected: value => PowerService.setProfile(parseInt(value))
            }
        }
    }
}
