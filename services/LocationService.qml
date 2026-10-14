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

    // The answer, judged in one place once curl's output and exit are both
    // in: stdout and the exit status used to set the error text in two
    // handlers, and which one the user saw depended on which signal came last.
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
        onTriggered: root.runSearch()
    }

    // A search still out is stopped, and the next one starts once it has
    // exited: stopped and started in the same turn, the new run could be
    // lost, and the stopped one's failure was shown under the new query.
    function runSearch() {
        if (searchProc.running) {
            searchProc.stale = true
            searchProc.running = false
            return
        }
        if (query.length < 2) { busy = false; return }
        searchProc.stale = false
        searchProc.requestQuery = query
        searchProc.command = ["curl", "-fsS", "--max-time", "10", Logic.geocodeUrl(query)]
        busy = true
        searchProc.running = true
    }

    Process {
        id: ipProc
        stderr: ErrorLog { label: "LocationService.ipProc" }
        command: ["curl", "-fsS", "--max-time", "8", Logic.IP_LOCATION_URL]
        // The output may arrive before or after the exit; judge once both are in.
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function done() {
            if (outputDone && exitCode >= 0) root.finish(exitCode, output)
        }
        stdout: StdioCollector { onStreamFinished: { ipProc.output = text; ipProc.outputDone = true; ipProc.done() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => { exitCode = code; done() }
    }

    Process {
        id: searchProc
        stderr: ErrorLog { label: "LocationService.searchProc" }
        // The query this run was started for.
        property string requestQuery: ""
        // Stopped for a newer query, which starts once this run is gone.
        property bool stale: false
        property string output: ""
        property bool outputDone: false
        property int exitCode: -1
        function done() {
            if (stale || !outputDone || exitCode < 0) return
            root.busy = false
            if (requestQuery !== root.query) return
            if (exitCode !== 0) {
                root.results = []
                root.error = "Location search unavailable"
                return
            }
            try {
                root.results = Logic.parseGeocode(output)
                root.error = root.results.length ? "" : "No location found"
            } catch (parseError) {
                root.results = []
                root.error = "Unreadable response"
            }
        }
        stdout: StdioCollector { onStreamFinished: { searchProc.output = text; searchProc.outputDone = true; searchProc.done() } }
        onStarted: { output = ""; outputDone = false; exitCode = -1 }
        onExited: code => {
            exitCode = code
            if (stale) Qt.callLater(root.runSearch)
            else done()
        }
    }
}
