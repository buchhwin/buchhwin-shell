pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "weather/WeatherLogic.js" as Logic

// City search for the weather location (Open-Meteo geocoding), and the
// approximate place by IP address (ipinfo.io). The chosen place is stored only
// in the user's settings.json, rounded to ~1 km.
Singleton {
    id: root
    property string query: ""
    property var results: []
    property bool busy: false
    property string error: ""

    // By IP: on request, and by itself when weather.autoLocate is on and no
    // place is set yet - never over one the user chose, and never in a nested
    // test session, which must not reach the network for this.
    //
    // Only once the network is up: the session starts before the Wi-Fi is
    // connected, and a request at that moment failed and was never repeated.
    // A failed automatic try is repeated when the network comes back, a few
    // times at most; a successful one is the last.
    readonly property bool autoLocate: SettingsService.value("weather.autoLocate")
    readonly property bool nested: Quickshell.env("BUCHHWIN_NESTED") === "1"
    readonly property bool wantsAutoLocate: SettingsService.loaded && autoLocate && !nested
        && WeatherService.enabled && !WeatherService.hasLocation && NetworkService.connected
    readonly property int autoLocateLimit: 3
    property int autoLocateTries: 0
    property bool autoLocateDone: false
    property bool detecting: false
    property bool detectingAutomatically: false
    property string detectError: ""
    onWantsAutoLocateChanged: tryAutoLocate()
    Component.onCompleted: tryAutoLocate()

    function tryAutoLocate() {
        if (!wantsAutoLocate || autoLocateDone || autoLocateTries >= autoLocateLimit || ipProc.running) return
        autoLocateTries += 1
        start(true)
    }

    function detectByIp() { start(false) }

    function start(automatic) {
        if (ipProc.running) return
        detectError = ""
        detecting = true
        detectingAutomatically = automatic
        ipProc.running = true
    }

    // The answer, judged in one place once curl has exited: stdout and the
    // exit status used to set the error text in two handlers, and which one
    // the user saw depended on which signal came last.
    function finish(exitCode, text) {
        detecting = false
        if (exitCode !== 0) { detectError = "Location by IP unavailable"; return }
        const place = Logic.parseIpLocation(text)
        if (!place) { detectError = "Could not tell where this connection is"; return }
        // A place picked while the request was out wins over an automatic one.
        if (detectingAutomatically && WeatherService.hasLocation) { autoLocateDone = true; return }
        if (!WeatherService.setLocation(place.name, place.lat, place.lon)) { detectError = "Unusable location"; return }
        if (detectingAutomatically) autoLocateDone = true
    }

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
        id: ipProc
        stderr: ErrorLog { label: "LocationService.ipProc" }
        command: ["curl", "-fsS", "--max-time", "8", Logic.IP_LOCATION_URL]
        stdout: StdioCollector { id: ipOutput }
        onExited: (exitCode, exitStatus) => root.finish(exitCode, ipOutput.text)
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
