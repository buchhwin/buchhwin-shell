pragma Singleton
import Quickshell
import QtQuick
import "timer/TimerLogic.js" as Logic

// One countdown, shown in the notch strip while it runs (NotchStrip's timer
// chip) and announced by a notification when it ends. Started from the
// launcher ("Timer: 5 minutes") or over IPC (`buchhwin timer start 5m`).
// The clock ticks once a second, and only while a timer runs.
Singleton {
    id: root

    property real endsAt: 0
    property int total: 0
    property real now: Date.now()
    readonly property bool running: endsAt > 0
    readonly property real remaining: running ? Math.max(0, endsAt - now) : 0
    readonly property string remainingText: running ? Logic.remainingText(remaining) : ""
    readonly property real fraction: running ? Logic.fraction(remaining, total) : 0
    readonly property bool realSession: Quickshell.env("BUCHHWIN_NESTED") !== "1"

    function start(seconds) {
        const s = Math.round(Number(seconds) || 0)
        if (s <= 0 || s > Logic.MAX_SECONDS) return false
        now = Date.now()
        total = s
        endsAt = now + s * 1000
        return true
    }
    // A typed duration ("5m", "1:30", "25"), as the launcher and IPC take it.
    function startText(text) { return start(Logic.parseDuration(text)) }
    function stop() { endsAt = 0; total = 0 }

    function finish() {
        const what = Logic.label(total)
        stop()
        if (realSession) Quickshell.execDetached(["notify-send", "--app-name=Timer", "--icon=alarm-symbolic",
                                                  "--urgency=critical", "--", "Timer done", "The " + what + " timer has run out"])
        else console.info("buchhwin-shell: timer: notification (nested, not sent):", what)
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            if (root.now >= root.endsAt) root.finish()
        }
    }
}
