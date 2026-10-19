import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.shell.components
import "../../services/system/SystemLogic.js" as Logic

// CPU, RAM and disk pills/widgets: usage bars, load average, the busiest
// processes and a button for the system monitor app. Below the meters the
// sensors this machine has - how hot the CPU, the GPU and the disk are, the
// GPU's load and the fan - and how fast the network goes, read only while
// the popup is open (SystemStatsService, SensorLogic).
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
        Component.onCompleted: {
            SystemStatsService.track()
            SystemStatsService.trackProcesses()
            SystemStatsService.trackSensors()
            SystemStatsService.trackDisk()
            SystemStatsService.trackNetwork()
        }
        Component.onDestruction: {
            SystemStatsService.untrack()
            SystemStatsService.untrackProcesses()
            SystemStatsService.untrackSensors()
            SystemStatsService.untrackDisk()
            SystemStatsService.untrackNetwork()
        }

        CardSection {
            Layout.fillWidth: true
            SystemMeters { Layout.fillWidth: true }
        }

        // One line per reading the machine has: a laptop without a fan
        // sensor, or a desktop without a GPU load file, leaves the row out
        // rather than showing a dash.
        readonly property var sensorRows: {
            const rows = []
            const temp = (glyph, label, value, extra) => {
                if (isFinite(value)) rows.push({ glyph: glyph, label: label, value: SystemStatsService.formatTemp(value),
                                                 extra: extra || "", level: SystemStatsService.tempLevel(value) })
            }
            temp("\u{f050f}", "CPU", SystemStatsService.cpuTemp)
            temp("\u{f08ae}", "GPU", SystemStatsService.gpuTemp,
                 isFinite(SystemStatsService.gpuBusy) ? SystemStatsService.percent(SystemStatsService.gpuBusy) + " busy" : "")
            if (!isFinite(SystemStatsService.gpuTemp) && isFinite(SystemStatsService.gpuBusy))
                rows.push({ glyph: "\u{f08ae}", label: "GPU", value: SystemStatsService.percent(SystemStatsService.gpuBusy), extra: "", level: "" })
            temp("\u{f02ca}", "Disk", SystemStatsService.diskTemp)
            if (isFinite(SystemStatsService.fanRpm))
                rows.push({ glyph: "\u{f0210}", label: "Fan", value: SystemStatsService.fanRpm > 0 ? SystemStatsService.fanRpm + " rpm" : "Off",
                            extra: "", level: "" })
            const net = SystemStatsService.netRates
            if (net) rows.push({ glyph: "\u{f04e2}", label: "Network", value: "\u2193 " + SystemStatsService.formatRate(net.rx),
                                 extra: "\u2191 " + SystemStatsService.formatRate(net.tx), level: "" })
            return rows
        }

        CardSection {
            Layout.fillWidth: true
            visible: stats.sensorRows.length > 0
            spacing: Metrics.spaceXs
            // Named as the processes' card is: under the meters, "CPU 39°"
            // and "Disk 29°" read as the meters' "CPU 1%" and "Disk 38%" again.
            SectionLabel { Layout.fillWidth: true; text: "Sensors" }
            // A row per reading, kept by position: the list is new on every
            // tick, and its length changes only when a reading comes or goes.
            Repeater {
                model: stats.sensorRows.length
                RowLayout {
                    id: sensor
                    required property int index
                    readonly property var entry: stats.sensorRows[index] || ({ glyph: "", label: "", value: "", extra: "", level: "" })
                    Layout.fillWidth: true
                    spacing: Metrics.spaceSm
                    ShellIcon {
                        glyph: sensor.entry.glyph
                        size: Metrics.iconSm
                        color: sensor.entry.level === "danger" ? Colors.danger : sensor.entry.level === "warning" ? Colors.warning : Colors.mutedText
                    }
                    ShellText { Layout.fillWidth: true; text: sensor.entry.label }
                    ShellText {
                        visible: sensor.entry.extra.length > 0
                        text: sensor.entry.extra
                        role: "small"; muted: true
                        font.features: { "tnum": 1 }
                    }
                    ShellText {
                        Layout.minimumWidth: Metrics.statColumnWidth
                        horizontalAlignment: Text.AlignRight
                        text: sensor.entry.value
                        font.features: { "tnum": 1 }
                    }
                }
            }
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
