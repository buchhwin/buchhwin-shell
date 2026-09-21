pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "weather/WeatherLogic.js" as Logic

// City search for the weather location (Open-Meteo geocoding). The chosen
// place is stored only in the user's settings.json, rounded to ~1 km.
Singleton {
    id: root
    property string query: ""
    property var results: []
    property bool busy: false
    property string error: ""

    function search(text) {
        query = String(text || "").trim()
        error = ""
        if (query.length < 2) {
            results = []
            debounce.stop()
            return
        }
        debounce.restart()
    }

    function select(result) {
        if (!result) return false
        const ok = WeatherService.setLocation(result.name, result.lat, result.lon)
        if (ok) {
            results = []
            query = ""
        }
        return ok
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: {
            searchProc.running = false
            searchProc.requestQuery = root.query
            searchProc.command = ["curl", "-fsS", "--max-time", "10", Logic.geocodeUrl(root.query)]
            root.busy = true
            searchProc.running = true
        }
    }

    Process {
        id: searchProc
        stderr: ErrorLog { label: "LocationService.searchProc" }
        property string requestQuery: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (searchProc.requestQuery !== root.query) return
                try {
                    root.results = Logic.parseGeocode(text)
                    root.error = root.results.length ? "" : "No location found"
                } catch (parseError) {
                    root.results = []
                    root.error = "Unreadable response"
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            if (exitCode !== 0 && searchProc.requestQuery === root.query) {
                root.results = []
                root.error = "Location search unavailable"
            }
        }
    }
}
