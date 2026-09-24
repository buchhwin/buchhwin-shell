import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/notifications/NotificationLogic.js" as N

ShellRoot {
    Component.onCompleted: {
        const free = { suppressed: false, dndMode: "off" }
        const timed = { suppressed: true, dndMode: "1h" }
        const manual = { suppressed: true, dndMode: "manual" }
        const auto = { suppressed: true, dndMode: "off" }

        T.eq(N.shouldPopup(free, false), true, "nothing suppressed: a normal notification pops up")
        T.eq(N.shouldPopup(free, true), true, "nothing suppressed: a critical notification pops up")
        T.eq(N.shouldPopup(timed, false), false, "timed DND hides a normal notification")
        T.eq(N.shouldPopup(timed, true), true, "timed DND still shows a critical one")
        T.eq(N.shouldPopup(manual, true), false, "manual DND silences even a critical one")
        T.eq(N.shouldPopup(auto, false), false, "fullscreen or game suppression hides a normal one")
        T.eq(N.shouldPopup(auto, true), true, "fullscreen or game suppression lets a critical one through")

        // Per-app rules decide before the suppression state does.
        T.eq(N.shouldPopup(free, false, "mute"), false, "a muted app never pops up")
        T.eq(N.shouldPopup(free, true, "mute"), false, "not even when the sender marks it critical")
        T.eq(N.shouldPopup(timed, false, "critical"), true, "an always-urgent app gets through timed DND")
        T.eq(N.shouldPopup(manual, false, "critical"), false, "manual DND still silences everything")
        T.eq(N.shouldPopup(auto, false, "critical"), true, "and through fullscreen or game suppression")
        T.eq(N.shouldPopup(free, false, "default"), true, "no rule behaves as before")

        T.eq(N.appKey({ appName: "  Signal " }), "signal", "an app key is the trimmed lower-case name")
        T.eq(N.appKey({}), "__system", "a notification without an app is the system")
        T.eq(N.ruleFor({ signal: "mute" }, { appName: "Signal" }), "mute", "a rule is found by app key")
        T.eq(N.ruleFor({ signal: "nonsense" }, { appName: "Signal" }), "default", "an unknown rule falls back")
        T.eq(N.ruleFor(null, { appName: "Signal" }), "default", "no rules at all falls back")

        const history = [{ appName: "Signal", summary: "Anna", body: "see you at six" },
                         { appName: "Updates", summary: "12 packages", body: "" }]
        T.eq(N.search(history, "").length, 2, "an empty query keeps everything")
        T.eq(N.search(history, "  ").length, 2, "so does a blank one")
        T.eq(N.search(history, "signal").map(item => item.summary), ["Anna"], "the app name matches")
        T.eq(N.search(history, "PACK").map(item => item.summary), ["12 packages"], "the summary matches, ignoring case")
        T.eq(N.search(history, "at six").map(item => item.summary), ["Anna"], "the body matches")
        T.eq(N.search(history, "nothing").length, 0, "no match is no rows")

        T.eq(N.withPopup([], "a", 3), ["a"], "the first popup enters an empty queue")
        T.eq(N.withPopup(["a", "b"], "c", 3), ["a", "b", "c"], "newest popup goes last")
        T.eq(N.withPopup(["a", "b", "c"], "d", 3), ["b", "c", "d"], "the oldest popup drops out at the limit")
        T.eq(N.withPopup(["a"], "b", 0), ["b"], "a broken limit still keeps the newest")

        T.eq(N.livePopups(["a", "b"], ["b", "c"]), ["b"], "a dismissed notification leaves the queue")
        T.eq(N.livePopups(["a"], ["a"]), ["a"], "a tracked notification stays")
        T.eq(N.livePopups(["a"], []), [], "an empty server list clears the queue")
        T.eq(N.livePopups([], ["a"]), [], "an empty queue stays empty")

        // What the notch shows for the newest popup, from the notification
        // itself: the picture by the card's route, else a bell.
        const icons = name => "/icons/" + name + ".png"
        T.eq(N.notchContent({ image: "/tmp/shot.png", appIcon: "signal", summary: "Anna", appName: "Signal", body: "six" }, icons),
             { kind: "notification", icon: "", iconSource: "/tmp/shot.png", title: "Anna", subtitle: "six" },
             "the image the notification brought comes first")
        T.eq(N.notchContent({ appIcon: "signal", summary: "Anna", appName: "Signal" }, icons).iconSource,
             "/icons/signal.png", "else the app icon, resolved by the caller")
        T.eq(N.notchContent({ appName: "Updates", body: "12 packages" }, icons),
             { kind: "notification", icon: "󰂚", iconSource: "", title: "Updates", subtitle: "12 packages" },
             "else a bell, and the app name stands in for a missing summary")
        T.eq(N.notchContent({ appIcon: "nonsense" }, name => "").icon, "󰂚",
             "an app icon that resolves to nothing is a bell too, like on the card")
        T.eq(N.notchContent(null, icons).title, "Notification", "no notification at all does not throw")

        T.finish("NotificationPopupTest")
    }
}
