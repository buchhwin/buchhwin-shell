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
    // The charge limit is read when the popup opens, and only then.
    onShownChanged: if (shown) PowerService.refreshChargeLimit()

    body: ColumnLayout {
        spacing: Metrics.pageGap

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
                    textFormat: Text.PlainText
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

            // The battery's bar is as thick here as on the control center's
            // tile (`progressTrack`, the level bars' token), and it turns red at
            // the same level as everywhere else. Charging is the green or the
            // accent (Settings > Power > Status colors).
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Metrics.progressTrack
                radius: height / 2
                color: Colors.track
                Rectangle {
                    width: parent.width * PowerService.percent / 100
                    height: parent.height
                    radius: parent.radius
                    color: PowerService.charging ? Colors.positiveFill
                        : PowerService.low ? Colors.danger : Colors.accentFill
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
            // Beside the health, the other number that says how this battery
            // is kept: why it stops at 80% on the charger, or that it is on
            // its way to 100% this once. Not while the header says "Charge
            // limit 80% reached" already.
            RowLayout {
                visible: (PowerService.chargeLimit.active || PowerService.chargeOnceActive) && !PowerService.limitReached
                Layout.fillWidth: true
                ShellText { Layout.fillWidth: true; text: "Charge limit"; role: "small"; muted: true }
                ShellText {
                    text: PowerService.chargeOnceActive ? "100% this once" : PowerService.chargeLimit.end + "%"
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
            // Compact like the Profile popup's modes: three full labels do not
            // fit the popup's width and were cut to "Po…", "Bal…" and "Perf…".
            // The chosen profile keeps its name, the others their glyph and
            // their name as a tooltip.
            SegmentedControl {
                focusOnTab: true
                Layout.fillWidth: true
                compact: true
                current: String(PowerService.profile)
                options: [
                    { value: String(PowerProfile.PowerSaver), label: "Power saver", icon: "󰌪" },
                    { value: String(PowerProfile.Balanced), label: "Balanced", icon: "󰾅" }
                ].concat(PowerService.hasPerformance ? [{ value: String(PowerProfile.Performance), label: "Performance", icon: "󰓅" }] : [])
                onSelected: value => PowerService.setProfile(parseInt(value))
            }
        }

        // Where the battery applets of other desktops keep "block sleep":
        // one switch, and how long it holds while it runs. On, it starts the
        // way the last chosen hold ended (an hour until one was chosen);
        // the other ways are on the control center's Power page and in
        // Settings > Power.
        CardSection {
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            SettingRow {
                Layout.fillWidth: true
                labelFills: true
                label: "Stay awake"
                hint: "Pauses screen off, lock and sleep"
                ShellToggle {
                    focusOnTab: true
                    checked: IdleService.stayAwake
                    onToggled: value => { if (value !== IdleService.stayAwake) IdleService.toggleStayAwake() }
                }
            }
            ShellText {
                Layout.fillWidth: true
                visible: IdleService.stayAwake
                text: IdleService.stayAwakeSubtitle
                role: "small"; muted: true
            }
        }
    }
}
