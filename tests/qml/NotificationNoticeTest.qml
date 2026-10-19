//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T
import "../../services/notifications/NotificationLogic.js" as Logic

// NotificationService's own notices (postNotice: what came while it was
// quiet, IPC `notifications notice`) and what a card asks the service of a
// notification (describe, opensSource), beside the server's popups. Under
// the lock screen's shell id, so no notification server runs (pitfall 82):
// a notice needs none, and the queue is the service's own.
ShellRoot {
    id: root
    property int tries: 0
    property int runs: 0
    property var first: null
    property var pushed: null

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            root.tries += 1
            if (!NotificationService.stateLoaded && root.tries < 200) return
            stop()
            T.ok(NotificationService.stateLoaded, "the state is read in the sandbox")
            T.eq(NotificationService.server, null, "and no server runs")
            root.check()
        }
    }

    function check() {
        NotificationService.setDnd("off")
        const notice = NotificationService.postNotice({ summary: "3 notifications while Do Not Disturb was on",
                                                        actionText: "Show", run: () => { root.runs += 1 } })
        T.ok(notice !== null, "a notice is posted")
        T.eq([NotificationService.popups.length, NotificationService.notchPopup === notice], [1, true],
             "it is a popup like the others, and the notch's newest")
        T.eq([notice.internal, notice.appName, notice.summary, notice.body, notice.expireTimeout],
             [true, "Notifications", "3 notifications while Do Not Disturb was on", "", -1], "what a card reads of it")
        T.eq(notice.actions.map(action => [action.identifier, action.text]), [["default", "Show"], ["show", "Show"]],
             "a click and a button, both Show")
        notice.actions[0].invoke()
        T.eq(root.runs, 1, "and either runs what it was given")
        T.eq(NotificationService.history.length, 0, "it is in no history")
        T.eq(NotificationService.report().notices, 1, "notifications get counts it")

        // The user's own Do Not Disturb: no notice, unless forced.
        NotificationService.setDnd("manual")
        T.eq(NotificationService.postNotice({ summary: "quiet" }), null, "Do Not Disturb holds a notice back")
        const forced = NotificationService.postNotice({ summary: "Timer done", urgent: true, force: true })
        T.ok(forced !== null, "a forced one gets through")
        NotificationService.setDnd("off")

        // Closed: out of the queue, and the object goes a moment later.
        NotificationService.hidePopup(forced)
        notice.dismiss()
        T.eq([NotificationService.popups.length, notice.retired, forced.retired], [0, true, true],
             "closed notices leave the queue and are retired")

        // Pushed out by newer popups: retired too.
        root.first = NotificationService.postNotice({ summary: "one" })
        NotificationService.postNotice({ summary: "two" })
        NotificationService.postNotice({ summary: "three" })
        root.pushed = NotificationService.postNotice({ summary: "four" })
        T.eq([NotificationService.popups.length, root.first.retired, root.pushed.retired], [3, true, false],
             "the oldest notice pushed out of three is retired")
        NotificationService.clearAll()
        T.eq(NotificationService.popups.length, 3, "Clear all leaves the notices: it clears the history")
        for (const item of NotificationService.popups.slice()) item.dismiss()
        T.eq(NotificationService.popups.length, 0, "dismissed one by one")

        // What a card asks of a notification that is no web app's.
        T.eq(NotificationService.describe({ appName: "Signal", appIcon: "signal-desktop", hints: {} }),
             { name: "Signal", icon: "signal-desktop", note: "" }, "a plain sender is itself")
        T.eq(NotificationService.describe(null), { name: "", icon: "", note: "" }, "nothing is nothing")
        T.eq(NotificationService.opensSource({ appName: "Signal" }), false, "and opens nothing of its own")
        // Handed on as a function, as the centre and Settings do.
        T.eq(Logic.group([{ id: 1, appName: "Signal", appIcon: "signal-desktop", hints: {} }], NotificationService.describe)
                 .map(entry => [entry.key, entry.name, entry.icon]), [["signal", "Signal", "signal-desktop"]],
             "the centre's groups are named through describe")
        T.eq(NotificationService.ruleRows().length, 0, "Settings lists no app in an empty sandbox")
        T.eq(NotificationService.opensSource({ appName: "Brave", desktopEntry: "brave-browser",
                                                hints: { "x-kde-origin-name": "github.com" } }), false,
             "nor does a site without a listed web app")

        // Nothing quiet in the sandbox, nothing kept, no sound.
        const report = NotificationService.report()
        T.eq([report.screenShares, report.quietReason, report.popupScreen, report.keepHistory, report.earlier, report.sounds],
             [0, "", "", false, 0, false], "the lock process watches no share and keeps nothing")
        T.eq(NotificationService.listed, 0, "the centre has nothing to list")

        // The retired objects go a moment later.
        destroyed.start()
    }

    Timer {
        id: destroyed
        interval: 1300
        onTriggered: {
            T.eq(root.first, null, "a retired notice is destroyed")
            T.finish("NotificationNoticeTest")
        }
    }
}
