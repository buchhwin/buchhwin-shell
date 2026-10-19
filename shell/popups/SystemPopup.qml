import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/system/SystemLogic.js" as Logic

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
        id: stats
        spacing: Metrics.pageGap
        // How many CPUs the per-process figures are shares of (each is a
        // share of one CPU, as top gives it), from the CPU meter's own read
        // of /proc/stat (SystemLogic.cpuTimes).
        readonly property int cpus: SystemStatsService.lastCpu ? SystemStatsService.lastCpu.cpus || 1 : 1
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
                SectionLabel { Layout.preferredWidth: Metrics.statColumnWidth; horizontalAlignment: Text.AlignRight; text: "CPU" }
                SectionLabel { Layout.preferredWidth: Metrics.statColumnWidth; horizontalAlignment: Text.AlignRight; text: "Mem" }
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
                        Layout.minimumWidth: Metrics.statColumnWidth
                        horizontalAlignment: Text.AlignRight
                        // The whole machine's share, as the CPU meter above
                        // gives it: the process figure is per CPU, so one busy
                        // process read 54.8 % beside "CPU 5 %".
                        text: Logic.processShare(modelData.cpu, stats.cpus).toFixed(1) + "%"
                        role: "small"; muted: true
                        font.features: { "tnum": 1 }
                    }
                    ShellText {
                        Layout.minimumWidth: Metrics.statColumnWidth
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
