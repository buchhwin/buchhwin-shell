pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "weather/WeatherLogic.js" as Logic

// Weather from Open-Meteo for the city chosen in Settings > Weather. Requests
// only run while some UI tracks the weather (dashboard, widget); the last
// forecast is cached so the dashboard has data offline. Coordinates and URLs
// never go to the log.
Singleton {
    id: root

    readonly property bool enabled: SettingsService.value("weather.enabled")
    readonly property string locationName: SettingsService.value("weather.locationName")
    readonly property real lat: SettingsService.value("weather.lat")
    readonly property real lon: SettingsService.value("weather.lon")
    readonly property string unit: SettingsService.value("weather.unit")
    readonly property int refreshMinutes: Math.max(10, Math.min(180, SettingsService.value("weather.refreshMinutes")))
    readonly property bool hasLocation: locationName.length > 0 && Logic.validCoordinates(lat, lon)
    readonly property string locationKey: hasLocation ? Logic.roundCoordinate(lat) + "/" + Logic.roundCoordinate(lon) + "/" + unit : ""

    property int trackers: 0
    property var model: null
    property var updated: null
    property string cacheKey: ""
    property bool loading: false
    property bool failed: false
    // noLocation | disabled | loading | ok | stale (offline, showing cache) | error
    readonly property string status: !enabled ? "disabled"
        : !hasLocation ? "noLocation"
        : model && cacheKey === locationKey ? (failed ? "stale" : "ok")
        : loading ? "loading" : failed ? "error" : "loading"
    readonly property bool hasData: enabled && hasLocation && model !== null && cacheKey === locationKey

    readonly property var current: hasData ? model.current : null
    readonly property var daily: hasData ? model.daily : []
    readonly property var hourly: hasData ? Logic.upcomingHours(model.hourly, clock.date) : []
    readonly property string updatedText: updated ? Qt.formatTime(updated, "HH:mm") : ""

    function formatTemperature(value) { return Logic.formatTemperature(value) }
    function sampleHours(step, count) { return Logic.sampleHours(hourly, step, count) }

    function track() {
        trackers += 1
        refreshIfStale()
    }
    function untrack() { trackers = Math.max(0, trackers - 1) }

    function refreshIfStale() {
        if (!updated || cacheKey !== locationKey || Date.now() - updated.getTime() > 10 * 60000) refresh()
    }

    function refresh() {
        if (!enabled || !hasLocation) return
        if (fetchProc.running) {
            if (fetchProc.requestKey === locationKey) return
            // The stopped request still reports its end; ignore it.
            fetchProc.superseded += 1
            fetchProc.running = false
        }
        loading = true
        fetchProc.requestKey = locationKey
        fetchProc.command = ["curl", "-fsS", "--max-time", "15", Logic.forecastUrl(lat, lon, unit)]
        fetchProc.running = true
    }

    function setLocation(name, latitude, longitude) {
        if (!String(name).trim().length || !Logic.validCoordinates(latitude, longitude)) return false
        SettingsService.set("weather.lat", Logic.roundCoordinate(latitude))
        SettingsService.set("weather.lon", Logic.roundCoordinate(longitude))
        SettingsService.set("weather.locationName", String(name).trim())
        return true
    }

    function clearLocation() {
        SettingsService.set("weather.locationName", "")
        SettingsService.set("weather.lat", 0)
        SettingsService.set("weather.lon", 0)
        model = null
        cacheKey = ""
        updated = null
        cacheFile.setText("")
    }

    // Location, latitude and longitude are written one after another; wait for
    // the last of them before fetching.
    onLocationKeyChanged: {
        failed = false
        locationSettle.restart()
    }
    Timer {
        id: locationSettle
        interval: 200
        onTriggered: if (root.locationKey.length && root.trackers > 0) root.refresh()
    }

    SystemClock { id: clock; precision: SystemClock.Hours }

    Process {
        id: fetchProc
        stderr: ErrorLog { label: "WeatherService.fetchProc" }
        property string requestKey: ""
        property int superseded: 0
        stdout: StdioCollector {
            onStreamFinished: {
                // Failed requests (offline) produce no output; onExited flags them.
                if (fetchProc.requestKey !== root.locationKey || !text.trim().length) return
                try {
                    const parsed = Logic.parseForecast(text)
                    const now = new Date()
                    root.model = parsed
                    root.cacheKey = fetchProc.requestKey
                    root.updated = now
                    root.failed = false
                    cacheFile.setText(Logic.toCache(parsed, now, fetchProc.requestKey) + "\n")
                } catch (error) {
                    // Output of a stopped request may be cut off; only a
                    // completed request counts as a failure.
                    if (fetchProc.superseded > 0) return
                    root.failed = true
                    console.warn("buchhwin-shell: weather response unusable")
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (fetchProc.superseded > 0) {
                fetchProc.superseded -= 1
                return
            }
            root.loading = false
            if (exitCode !== 0) root.failed = true
        }
    }

    Timer {
        interval: root.refreshMinutes * 60000
        repeat: true
        running: root.trackers > 0 && root.hasLocation && root.enabled
        onTriggered: root.refresh()
    }

    FileView {
        id: cacheFile
        path: Paths.cacheDir + "/weather.json"
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.model !== null || !text().trim().length) return
            try {
                const cached = Logic.fromCache(text())
                root.model = cached.model
                root.updated = cached.updated
                root.cacheKey = cached.key
            } catch (error) {
                // A missing or outdated cache simply means no offline data.
            }
        }
    }
}
