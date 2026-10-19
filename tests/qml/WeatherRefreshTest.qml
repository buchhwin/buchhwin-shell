import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/weather/WeatherLogic.js" as W

// When the weather is fetched again besides its 30-minute timer: after the
// wall clock jumped (a resume - the timer slept too) and when the network
// comes back after a failed fetch. The service asks only while something
// shows the weather.
ShellRoot {
    Component.onCompleted: {
        const minute = 60000
        const evening = new Date(2026, 9, 18, 23, 30).getTime()
        T.ok(W.refreshWanted("jump", false, 0, evening), "nothing fetched yet: fetch")
        T.ok(W.refreshWanted("jump", false, evening, new Date(2026, 9, 19, 8, 0).getTime()),
             "the evening's forecast in the morning: fetch")
        T.ok(!W.refreshWanted("jump", false, evening, evening + 3 * minute),
             "a jump of minutes within the same hour: keep it")
        T.ok(W.refreshWanted("jump", false, new Date(2026, 9, 18, 23, 58).getTime(), new Date(2026, 9, 19, 0, 1).getTime()),
             "a jump into the next hour: the hourly strip starts there, fetch")
        T.ok(W.refreshWanted("online", true, evening, evening + minute), "back online after a failed fetch: fetch at once")
        T.ok(!W.refreshWanted("online", false, evening, evening + 5 * minute), "back online with a fresh forecast: keep it")
        T.ok(W.refreshWanted("online", false, evening, evening + 11 * minute), "back online with an old one: fetch")
        T.finish("WeatherRefreshTest")
    }
}
