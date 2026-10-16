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

    // Whether this one samples. On the desktop, the bar and the notch it is
    // always on screen; a host that is not binds this to whether it is shown
    // (the dashboard, while open). Tracked from creation, a card on a closed
    // dashboard kept /proc read every 2 s and `df` run every 30 s for the
    // whole session. The first sync waits a turn: hosts hand over what they
    // set in the Loader's `onLoaded`, which comes after `onCompleted`.
    property bool sampling: true
    property bool tracked: false
    onSamplingChanged: syncTracking()
    Component.onCompleted: Qt.callLater(root.syncTracking)
    Component.onDestruction: if (tracked) SystemStatsService.untrack()
    function syncTracking() {
        if (sampling === tracked) return
        tracked = sampling
        if (tracked) SystemStatsService.track()
        else SystemStatsService.untrack()
    }

    icon: metric === "ram" ? "󰍛" : metric === "disk" ? "󰋊" : "󰻠"
    label: SystemStatsService.percent(usage)
    iconColor: usage > 0.9 ? root.dangerInk : usage > 0.75 ? root.warningInk : root.glyphInk
    // What a bigger cell is worth here: the name, so a row of three of these
    // can be read without knowing the glyphs; a bar, because a number alone
    // does not say whether 62 % is a lot; and how much of the thing there
    // actually is.
    name: metric === "ram" ? "RAM" : metric === "disk" ? "Disk" : "CPU"
    meter: usage
    meterColor: usage > 0.9 ? root.dangerInk : usage > 0.75 ? root.warningInk : Colors.accent
    detail: metric === "ram" && SystemStatsService.memory
            ? SystemStatsService.formatBytes(SystemStatsService.memory.used * 1024) + " of "
              + SystemStatsService.formatBytes(SystemStatsService.memory.total * 1024)
        : metric === "disk" && SystemStatsService.disk
            ? SystemStatsService.formatBytes(SystemStatsService.disk.total - SystemStatsService.disk.used) + " free"
        : ""
}
