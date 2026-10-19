pragma Singleton
import Quickshell
import QtQuick
import "time/SunLogic.js" as Logic
import "weather/WeatherLogic.js" as WeatherLogic
import "appearance/TimeFormat.js" as TimeFormat

// Sunrise and sunset at the weather place, for the theme's "Sunset to
// sunrise" (Settings > Appearance: Automatic, `appearance.autoTheme` "sun").
// The place is the one Night Light's sun mode uses (Settings > Weather);
// gammastep does Night Light's sums itself and tells nobody, so the theme
// has its own (services/time/SunLogic.js).
//
// It costs nothing unless the theme asks for it: then one computation per
// change - a timer to the next sunrise or sunset (at most twelve hours, so a
// moved place or another time zone is seen within that), armed again when
// the wall clock jumps (WallClock.qml: a night in suspend). The lock face
// reaches this through Colors and reads the same settings; nothing here
// writes anything.
Singleton {
    id: root

    readonly property bool bySun: SettingsService.value("appearance.autoTheme") === "sun"
    readonly property bool wanted: bySun && SettingsService.theme === "auto"
    // The weather place, as WeatherService.hasLocation has it, read from the
    // settings directly: asking WeatherService would build it (and its
    // fetches) wherever only the theme is drawn.
    readonly property string placeName: SettingsService.value("weather.locationName")
    readonly property real lat: SettingsService.value("weather.lat")
    readonly property real lon: SettingsService.value("weather.lon")
    readonly property bool known: placeName.length > 0 && WeatherLogic.validCoordinates(lat, lon)

    // Whether it is night at the place, once computed; `ready` says the
    // answer is the sun's (the theme falls back on the hours otherwise).
    property bool night: false
    property bool ready: false
    // Today's two times (Dates, null on a polar day or night) and the next
    // change, for Settings to show.
    property var sunrise: null
    property var sunset: null
    property var nextChange: null
    property string polar: ""

    // One line for Settings under the choice: when today turns dark and
    // light, or why it cannot.
    readonly property string summary: {
        if (!bySun) return ""
        if (!known) return "Needs a weather place: Settings > Weather"
        if (polar === "day") return "The sun does not set here today"
        if (polar === "night") return "The sun does not rise here today"
        if (!sunrise || !sunset) return ""
        const twelve = SettingsService.twelveHourClock
        return "Today: light from " + TimeFormat.time(sunrise, twelve) + ", dark from " + TimeFormat.time(sunset, twelve)
    }

    function update() {
        if (!bySun || !known) {
            ready = false
            sunrise = null
            sunset = null
            nextChange = null
            polar = ""
            timer.stop()
            return
        }
        const now = new Date()
        const found = Logic.state(now, lat, lon)
        if (!found) { ready = false; timer.stop(); return }
        night = found.night
        sunrise = found.sunrise
        sunset = found.sunset
        nextChange = found.next
        polar = found.polar
        ready = true
        // Only the theme needs the next change on time; the summary for
        // Settings is today's and is read when the page is open.
        if (wanted) {
            timer.interval = Logic.wait(now, found.next)
            timer.restart()
        } else {
            timer.stop()
        }
    }

    // Debounced through callLater: a profile switch writes theme, choice and
    // place in one go.
    onBySunChanged: Qt.callLater(update)
    onWantedChanged: Qt.callLater(update)
    onKnownChanged: Qt.callLater(update)
    onLatChanged: Qt.callLater(update)
    onLonChanged: Qt.callLater(update)

    Connections {
        target: WallClock
        function onJumped() { if (root.bySun) root.update() }
    }

    Timer {
        id: timer
        onTriggered: root.update()
    }

    Component.onCompleted: update()
}
