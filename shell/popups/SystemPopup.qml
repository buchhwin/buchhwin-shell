import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components

// CPU, RAM and disk pills/widgets: usage bars, load average, the busiest
// processes and a button for the system monitor app.
PopupPanel {
    id: root
    panelId: "systemPopup"
    heading: "System"
    detail: SystemStatsService.load.length ? "Load " + SystemStatsService.load.map(value => value.toFixed(2)).join("  ") : ""
    glyph: "󰻠"
    footerText: SystemStatsService.monitorApp ? "Open " + SystemStatsService.monitorApp.name : ""
    footerGlyph: "󰄪"
    onFooterClicked: SystemStatsService.openMonitor()

    body: ColumnLayout {
        spacing: Metrics.panelGap
        Component.onCompleted: { SystemStatsService.track(); SystemStatsService.trackProcesses() }
        Component.onDestruction: { SystemStatsService.untrack(); SystemStatsService.untrackProcesses() }

        CardSection {
            Layout.fillWidth: true
            SystemMeters { Layout.fillWidth: true }
        }

        CardSection {
            Layout.fillWidth: true
            spacing: Metrics.spaceXxs

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.spaceSm
                Layout.rightMargin: Metrics.spaceSm
                SectionLabel { Layout.fillWidth: true; text: "Top processes" }
                SectionLabel { Layout.preferredWidth: Metrics.iconXl * 1.5; horizontalAlignment: Text.AlignRight; text: "CPU" }
                SectionLabel { Layout.preferredWidth: Metrics.iconXl * 1.5; horizontalAlignment: Text.AlignRight; text: "Mem" }
            }
            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.spaceSm
                visible: SystemStatsService.processes.length === 0
                row: true
                icon: Icons.busy
                title: "Measuring …"
            }
            Repeater {
                model: SystemStatsService.processes
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: Metrics.spaceSm
                    Layout.rightMargin: Metrics.spaceSm
                    Layout.preferredHeight: Metrics.controlHeightSm
                    ShellText { Layout.fillWidth: true; text: modelData.name; role: "small" }
                    ShellText {
                        Layout.minimumWidth: Metrics.iconXl * 1.5
                        horizontalAlignment: Text.AlignRight
                        text: modelData.cpu.toFixed(1) + "%"
                        role: "small"; muted: true
                        font.features: { "tnum": 1 }
                    }
                    ShellText {
                        Layout.minimumWidth: Metrics.iconXl * 1.5
                        horizontalAlignment: Text.AlignRight
                        text: modelData.memory.toFixed(1) + "%"
                        role: "small"; muted: true
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
