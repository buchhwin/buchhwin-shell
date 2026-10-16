import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/weather/WeatherLogic.js" as W

ShellRoot {
    id: root
    FileView { id: forecast; path: Qt.resolvedUrl("../fixtures/openmeteo-forecast.json").toString().replace("file://", ""); blockLoading: true }

    // ---- the cache is the user's alone (security#8) ---------------------------
    // Its key is the place's coordinates. Run on a file in the runner's
    // sandboxed cache, never the real one, and without the service: the
    // command it runs, then an atomic write over the file the way the service
    // writes it (QSaveFile keeps the mode of the file it replaces).
    readonly property string cache: Quickshell.env("XDG_CACHE_HOME") || ""
    readonly property string dir: cache + "/weather-privacy"
    readonly property string file: dir + "/weather.json"
    property int step: 0
    Process {
        id: shell
        property string output: ""
        stdout: StdioCollector { onStreamFinished: shell.output = text }
        onExited: next.start()
    }
    Timer { id: next; interval: 20; onTriggered: root.advance() }
    FileView { id: written; atomicWrites: true; printErrors: false; onSaved: next.start() }
    function run(command) {
        shell.output = ""
        shell.command = command
        shell.running = true
    }
    function advance() {
        step += 1
        if (step === 1) {
            run(["sh", "-c", "mkdir -p \"$1\" && printf '{}\\n' > \"$2\" && chmod 644 \"$2\"", "sh", dir, file])
        } else if (step === 2) {
            run(W.privateFileCommand(file))
        } else if (step === 3) {
            run(["stat", "-c", "%a", file])
        } else if (step === 4) {
            T.eq(shell.output.trim(), "600", "a cache from before is made the user's alone")
            written.path = file
            written.setText("{\"version\": 1}\n")
        } else if (step === 5) {
            run(["stat", "-c", "%a", file])
        } else if (step === 6) {
            T.eq(shell.output.trim(), "600", "and stays so through an atomic write")
            run(W.privateFileCommand(dir + "/missing.json"))
        } else if (step === 7) {
            run(["sh", "-c", "[ -e \"$1\" ] && echo made || echo absent", "sh", dir + "/missing.json"])
        } else if (step === 8) {
            T.eq(shell.output.trim(), "absent", "a cache that is not there is not made")
            run(["sh", "-c", "rm -rf -- \"$1\"", "sh", dir])
        } else {
            T.finish("WeatherTest")
        }
    }

    Component.onCompleted: {
        // Requests
        T.eq(W.roundCoordinate(52.51998), 52.52, "coordinates round to two decimals")
        T.eq(W.roundCoordinate(-0.004), -0, "tiny negative rounds to zero")
        const url = W.forecastUrl(52.519, 13.404, "celsius")
        T.ok(url.indexOf("latitude=52.52&longitude=13.4&") > 0, "forecast url uses rounded coordinates")
        T.ok(url.indexOf("temperature_unit=celsius") > 0, "celsius unit")
        T.ok(W.forecastUrl(1, 2, "fahrenheit").indexOf("temperature_unit=fahrenheit") > 0, "fahrenheit unit")
        T.ok(W.forecastUrl(1, 2, "kelvin").indexOf("temperature_unit=celsius") > 0, "unknown unit falls back to celsius")
        T.ok(W.geocodeUrl(" Frankfurt am Main&x=1 ").indexOf("name=Frankfurt%20am%20Main%26x%3D1&") > 0, "geocode query is encoded and trimmed")
        T.ok(W.validCoordinates(52.52, 13.4), "valid coordinates")
        T.ok(!W.validCoordinates(0, 0), "null island means unset")
        T.ok(!W.validCoordinates(91, 0), "latitude range")
        T.ok(!W.validCoordinates("52", 13), "strings are not coordinates")

        // Conditions: every WMO code has an English label and day/night icon.
        const codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        T.ok(codes.every(code => W.condition(code, true).label !== "Unknown" && W.condition(code, false).icon.length > 0), "all WMO codes mapped")
        T.eq(W.condition(0, true).label, "Clear sky", "clear label")
        T.ok(W.condition(0, true).icon !== W.condition(0, false).icon, "clear sky has a night icon")
        T.eq(W.condition(12345, true).label, "Unknown", "unknown code")

        // Parsing
        const now = new Date(2026, 2, 10, 14, 45)
        const model = W.parseForecast(forecast.text(), now)
        T.eq(model.current.temperature, 8.4, "current temperature")
        T.eq(model.current.feelsLike, 5.9, "feels like")
        T.eq(model.current.label, "Overcast", "current condition")
        T.eq(model.current.humidity, 71, "humidity")
        T.eq(model.current.max, 10.2, "today's max from daily")
        T.eq(model.current.uv, 2.4, "today's uv")
        T.eq(model.hourly[0].time.getHours(), 14, "hourly starts at the current hour")
        T.eq(model.current.precipitation, model.hourly[0].precipitation, "current rain chance from current hour")
        T.eq(model.hourly.length, 34, "remaining fixture hours are kept")
        T.eq(model.daily.length, 7, "seven days")
        T.eq(model.daily[1].date.getDate(), 11, "daily dates are local days")
        T.eq(model.daily[0].sunrise.getHours(), 6, "sunrise parsed")
        T.eq(model.daily[6].max, null, "missing values become null")
        T.eq(model.daily[6].label, "Unknown", "unknown daily code")
        T.eq(W.sampleHours(model.hourly, 3, 8).map(hour => hour.time.getHours()), [14, 17, 20, 23, 2, 5, 8, 11], "three-hour samples")
        T.eq(W.upcomingHours(model.hourly, new Date(2026, 2, 10, 20, 10))[0].time.getHours(), 20, "cached hours age out")

        T.throwsError(() => W.parseForecast("{not json"), "broken json")
        T.throwsError(() => W.parseForecast({ error: true, reason: "x" }), "provider error")
        T.throwsError(() => W.parseForecast({ current: {} }), "incomplete forecast")

        // Cache round trip keeps dates and key.
        const cached = W.fromCache(W.toCache(model, now, "52.52/13.4/celsius"))
        T.eq(cached.key, "52.52/13.4/celsius", "cache key")
        T.eq(cached.updated.getTime(), now.getTime(), "cache timestamp")
        T.ok(cached.model.hourly[0].time instanceof Date && cached.model.hourly[0].time.getHours() === 14, "cached hour dates revived")
        T.ok(cached.model.daily[0].sunset instanceof Date, "cached daily dates revived")
        T.throwsError(() => W.fromCache(JSON.stringify({ version: 2 })), "unknown cache version")

        // Geocoding
        const places = W.parseGeocode({ results: [
            { name: "Berlin", admin1: "Land Berlin", country: "Deutschland", latitude: 52.52437, longitude: 13.41053 }, // private-data: public
            { name: "Kaputt", latitude: "x", longitude: 1 },
            { name: "Ohne Region", latitude: 1.5, longitude: 2.5 }
        ] })
        T.eq(places.length, 2, "invalid places dropped")
        T.eq(places[0], { name: "Berlin", region: "Land Berlin, Deutschland", lat: 52.52, lon: 13.41 }, "place normalised and rounded")
        T.eq(places[1].region, "", "missing region")
        T.eq(W.parseGeocode({}).length, 0, "no results")

        T.eq(W.formatTemperature(-0.4), "0°", "no negative zero")
        T.eq(W.formatTemperature(17.6), "18°", "rounded temperature")
        T.eq(W.formatTemperature(null), "–", "missing temperature")
        // Location by IP (ipinfo.io), with a made-up place: city, region and the
        // coordinates rounded like a searched place.
        T.eq(W.parseIpLocation('{"ip":"192.0.2.1","city":"Sampletown","region":"Exampleland","country":"XX","loc":"12.34,56.78"}'),
             { name: "Sampletown", region: "Exampleland, XX", lat: 12.34, lon: 56.78 }, "ipinfo answer read")
        T.eq(W.parseIpLocation({ region: "Exampleland", country: "XX", loc: "12.34,56.78" }).name, "Exampleland",
             "the region stands in for a missing city")
        T.eq([W.parseIpLocation("{nope"), W.parseIpLocation({ city: "A" }), W.parseIpLocation({ city: "A", loc: "1,2,3" }),
              W.parseIpLocation({ city: "A", loc: "120,10" }), W.parseIpLocation({ loc: "10,10" }), W.parseIpLocation(null)],
             [null, null, null, null, null, null], "no place, broken or impossible answers are no answer")
        T.ok(W.IP_LOCATION_URL.indexOf("https://") === 0, "asked over HTTPS")
        // Enter in the city search (ui-b#15): only results of the current query.
        const found = [{ name: "Berlin" }, { name: "Bernau" }]
        T.eq(W.firstResultFor("Ber", "Ber", found), found[0], "the current query's first place")
        T.eq(W.firstResultFor(" Ber ", "Ber", found), found[0], "outer spaces are not a new query")
        T.eq(W.firstResultFor("Bern", "Ber", found), null, "the previous query's places are not taken")
        T.eq([W.firstResultFor("Bern", "Bern", []), W.firstResultFor("B", "B", found), W.firstResultFor("", "", found)],
             [null, null, null], "nothing found, or nothing searched")

        T.eq(W.privateFileCommand("/c/weather.json").slice(-1), ["/c/weather.json"], "the cache's path is the last argument")
        // A sandbox cache only: the runner sets one under its own temporary
        // directory, and without it nothing here may run.
        if (cache.indexOf("buchhwin-qmltest") < 0) {
            T.ok(false, "XDG_CACHE_HOME is not the test runner's sandbox (" + cache + ")")
            T.finish("WeatherTest")
            return
        }
        advance()
    }
}
