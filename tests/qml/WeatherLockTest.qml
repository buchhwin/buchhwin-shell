//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// The lock screen's process shows the weather the shell fetched and fetches
// nothing itself: with a place set and something tracking, it starts no
// request (WeatherService.lockProcess). The place is an invented one.
ShellRoot {
    id: root
    property int tries: 0

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.tries += 1
            if (!SettingsService.loaded && root.tries < 200) return
            stop()
            T.ok(WeatherService.lockProcess, "the weather knows it runs in the lock's process")
            SettingsService.setAll({ "weather.enabled": true, "weather.lat": 12.34, "weather.lon": 56.78, // private-data: invented
                                     "weather.locationName": "Sample Town" })
            T.ok(WeatherService.hasLocation, "a place is set")
            WeatherService.track()
            T.eq(WeatherService.loading, false, "tracking it starts no request")
            WeatherService.refresh()
            T.eq(WeatherService.loading, false, "and neither does a refresh")
            WeatherService.untrack()
            T.finish("WeatherLockTest")
        }
    }
}
