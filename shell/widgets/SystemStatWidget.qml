import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// Optional CPU, RAM or disk usage from SystemStatsService, which samples only
// while such a widget (or the system popup) exists. Hidden by default and
// never part of a default profile.
WidgetBase {
    id: root
    readonly property string metric: instance && instance.options && instance.options.metric ? instance.options.metric
        : instance && instance.type ? instance.type : "cpu"
    readonly property real usage: SystemStatsService.usage(metric)

    Component.onCompleted: SystemStatsService.track()
    Component.onDestruction: SystemStatsService.untrack()

    icon: metric === "ram" ? "󰍛" : metric === "disk" ? "󰋊" : "󰻠"
    label: SystemStatsService.percent(usage)
    iconColor: usage > 0.9 ? Colors.danger : usage > 0.75 ? Colors.warning : root.textColor
    // What a bigger cell is worth here: the name, so a row of three of these
    // can be read without knowing the glyphs; a bar, because a number alone
    // does not say whether 62 % is a lot; and how much of the thing there
    // actually is.
    name: metric === "ram" ? "RAM" : metric === "disk" ? "Disk" : "CPU"
    meter: usage
    meterColor: usage > 0.9 ? Colors.danger : usage > 0.75 ? Colors.warning : Colors.accent
    detail: metric === "ram" && SystemStatsService.memory
            ? SystemStatsService.formatBytes(SystemStatsService.memory.used * 1024) + " of "
              + SystemStatsService.formatBytes(SystemStatsService.memory.total * 1024)
        : metric === "disk" && SystemStatsService.disk
            ? SystemStatsService.formatBytes(SystemStatsService.disk.total - SystemStatsService.disk.used) + " free"
        : ""
}
