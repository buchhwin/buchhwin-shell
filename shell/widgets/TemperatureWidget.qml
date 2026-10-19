import QtQuick
import qs.shell.widgets
import qs.theme
import qs.services

// How hot the CPU is, from the sensor SystemStatsService picked (SensorLogic):
// the figure, the name and a bar from the medium size up, and the GPU and the
// fan at large. Warm (80 °C) and hot (90 °C) colour the glyph. Hidden on a
// machine that has no CPU sensor, and never part of a default profile.
WidgetBase {
    id: root
    readonly property real celsius: SystemStatsService.cpuTemp
    readonly property string heat: SystemStatsService.tempLevel(celsius)
    // Shown until the sensors are found, then only where there is one.
    hasData: SystemStatsService.sensorPaths === null || SystemStatsService.sensorPaths.cpu.length > 0

    // Whether this one samples, as the CPU, RAM and disk widgets do: always
    // where it is on screen, while the dashboard is open there. The first sync
    // waits a turn for what a host hands over in its Loader's `onLoaded`.
    property bool sampling: true
    property bool tracked: false
    onSamplingChanged: syncTracking()
    Component.onCompleted: Qt.callLater(root.syncTracking)
    Component.onDestruction: if (tracked) SystemStatsService.untrackSensors()
    function syncTracking() {
        if (sampling === tracked) return
        tracked = sampling
        if (tracked) SystemStatsService.trackSensors()
        else SystemStatsService.untrackSensors()
    }

    icon: "\u{f050f}"
    label: isFinite(celsius) ? SystemStatsService.formatTemp(celsius) : "…"
    iconColor: heat === "danger" ? root.dangerInk : heat === "warning" ? root.warningInk : root.glyphInk
    name: "CPU"
    // 100 °C is the end of the bar: past it nothing reads any more.
    meter: isFinite(celsius) ? Math.max(0, Math.min(1, celsius / 100)) : -1
    meterColor: heat === "danger" ? root.dangerInk : heat === "warning" ? root.warningInk : root.levelFill
    detail: [isFinite(SystemStatsService.gpuTemp) ? "GPU " + SystemStatsService.formatTemp(SystemStatsService.gpuTemp) : "",
             isFinite(SystemStatsService.fanRpm) && SystemStatsService.fanRpm > 0 ? "Fan " + SystemStatsService.fanRpm + " rpm" : ""]
        .filter(part => part.length).join(" · ")
}
