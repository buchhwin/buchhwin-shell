import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services

// CPU, memory and disk one under the other: a glyph, a name, the figures and a
// bar. Two surfaces draw this - the system popup behind the bar's pill and the
// dashboard's "System" card - and for a while they drew it twice, from two
// forty-line copies that had already drifted apart: one said how much of the
// disk was used, the other how much was free. Two readouts of one number that
// disagree are worse than one that is merely terse.
//
// What actually differs between the two is here as properties; everything else
// is the same block.
ColumnLayout {
    id: root
    // How many of the three there is room for. A popup opens at the size it
    // needs and always shows all three; a dashboard cell is given its height
    // and works the count out from it.
    property int maxRows: 3
    // The figures beside each name are the first thing a narrow cell gives up:
    // the percentage is the point and "12.4 GB of 31.1 GB" is the footnote.
    property bool showDetail: true

    spacing: Metrics.spaceMd

    readonly property var stats: [
        { glyph: "󰻠", label: "CPU", usage: SystemStatsService.cpu, detail: "" },
        { glyph: "󰍛", label: "Memory", usage: SystemStatsService.ram,
          detail: SystemStatsService.memory
              ? SystemStatsService.formatBytes(SystemStatsService.memory.used * 1024)
                + " of " + SystemStatsService.formatBytes(SystemStatsService.memory.total * 1024) : "" },
        // "used of total", the same sentence as the line above it, so the two
        // rows can be read without noticing that one of them turned around.
        { glyph: "󰋊", label: "Disk", usage: SystemStatsService.diskUsage,
          detail: SystemStatsService.disk
              ? SystemStatsService.formatBytes(SystemStatsService.disk.used)
                + " of " + SystemStatsService.formatBytes(SystemStatsService.disk.total) : "" }
    ]

    Repeater {
        model: root.stats
        ColumnLayout {
            id: stat
            required property var modelData
            required property int index
            visible: index < root.maxRows
            Layout.fillWidth: true
            spacing: Metrics.spaceXs
            readonly property color barColor: modelData.usage > 0.9 ? Colors.danger
                : modelData.usage > 0.75 ? Colors.warning : Colors.accent

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.spaceSm
                ShellIcon { glyph: stat.modelData.glyph; size: Metrics.iconSm; color: Colors.mutedText }
                ShellText { text: stat.modelData.label }
                ShellText {
                    Layout.fillWidth: true
                    visible: root.showDetail
                    text: stat.modelData.detail
                    role: "small"; muted: true
                    elide: Text.ElideRight
                }
                // Without the detail line there is nothing to push the
                // percentage to the right edge, so this does it instead.
                Item { Layout.fillWidth: !root.showDetail }
                ShellText {
                    text: SystemStatsService.percent(stat.modelData.usage)
                    font.features: { "tnum": 1 }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Metrics.meterHeight
                radius: height / 2
                color: Colors.track
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, stat.modelData.usage))
                    height: parent.height
                    radius: parent.radius
                    color: stat.barColor
                    Behavior on width {
                        NumberAnimation { duration: Animations.move(Animations.control); easing.type: Animations.easing }
                    }
                }
            }
        }
    }
}
