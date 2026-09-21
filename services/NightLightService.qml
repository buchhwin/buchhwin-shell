pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "nightlight/NightLightLogic.js" as Logic

// Warmer screen colours through gammastep (wlr gamma control): always on, on a
// fixed schedule, or from sunset to sunrise at the weather location. Stopping
// the process restores normal colours.
Singleton {
    id: root

    readonly property string mode: SettingsService.value("nightLight.mode")
    readonly property int temperature: Logic.clampTemperature(SettingsService.value("nightLight.temperature"))
    readonly property string start: SettingsService.value("nightLight.start")
    readonly property string end: SettingsService.value("nightLight.end")
    readonly property bool scheduled: Logic.scheduleActive(start, end, clock.date)
    readonly property var command: Logic.command(mode, temperature, WeatherService.lat, WeatherService.lon, scheduled)
    readonly property bool active: command.length > 0
    readonly property bool running: gammastep.running
    readonly property bool sunNeedsLocation: mode === "sun" && !WeatherService.hasLocation
    readonly property string summary: mode === "off" ? "Off"
        : mode === "manual" ? "On · " + temperature + " K"
        : mode === "schedule" ? (scheduled ? "On until " + end : "From " + start)
        : sunNeedsLocation ? "Location missing" : "Sunset to sunrise"

    // Quick toggle: off <-> the last used automatic mode or manual.
    function toggle() {
        if (mode === "off") SettingsService.set("nightLight.mode", SettingsService.value("nightLight.lastMode"))
        else {
            SettingsService.set("nightLight.lastMode", mode)
            SettingsService.set("nightLight.mode", "off")
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // Restart when the command changes (mode, temperature, location). `active`
    // may not be re-evaluated yet inside this handler, so the timer decides.
    onCommandChanged: {
        gammastep.running = false
        restartTimer.restart()
    }
    Timer {
        id: restartTimer
        interval: 300
        onTriggered: if (root.active) { gammastep.command = root.command; gammastep.running = true }
    }

    // Crash restarts back off (10 s, 20 s, …) and stop after five failures,
    // e.g. when another tool holds the gamma control. A new command resets it.
    property int failures: 0
    onModeChanged: failures = 0
    Process {
        id: gammastep
        stderr: ErrorLog { label: "NightLightService.gammastep" }
        onRunningChanged: {
            if (running || !root.active || restartTimer.running) return
            root.failures += 1
            if (root.failures > 5) return
            crashTimer.interval = 10000 * Math.pow(2, root.failures - 1)
            crashTimer.restart()
        }
    }
    Timer { id: crashTimer; onTriggered: if (root.active && !gammastep.running) restartTimer.restart() }

    Component.onCompleted: if (active) restartTimer.restart()
}
