import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/timer/TimerLogic.js" as L
import qs.services
import qs.shell.widgets

// TimerService itself, in the runner's sandboxed state directory: a timer and
// a Focus session side by side, stopped and cancelled, written to timer.json
// and read back by a service that starts after the file was written (the
// shell restarted); and the bar's TimerWidget over it. No run is let end -
// an end would announce itself through NotificationService (pitfall 82); what
// an end does is TimerRunsTest's.
ShellRoot {
    id: root
    property int stage: 0
    property var stoppedKinds: []
    readonly property string boot: bootFile.text().trim()
    readonly property real seededAt: Date.now()

    FileView {
        id: bootFile
        path: "/proc/sys/kernel/random/boot_id"
        blockLoading: true
        printErrors: false
    }
    // The file a shell before the restart left: a timer with five minutes
    // to go and a session with fifteen. Written before the service is first
    // asked for anything, so it reads this at its start.
    FileView {
        id: seed
        path: Paths.stateDir + "/timer.json"
        atomicWrites: true
        printErrors: false
        onSaved: wait.start()
    }
    // Read back with a FileView whose path is set when it is wanted: one that
    // has read the file before can keep its old text (pitfall 91).
    FileView {
        id: readBack
        path: ""
        blockLoading: true
        printErrors: false
    }
    Loader {
        id: widget
        active: false
        sourceComponent: Component { TimerWidget {} }
    }
    Timer {
        id: wait
        interval: 50
        repeat: true
        onTriggered: root.advance()
    }

    function advance() {
        if (stage === 0) {
            stage = 1
            TimerService.stopped.connect(kind => { root.stoppedKinds = root.stoppedKinds.concat([kind]) })
            return
        }
        if (stage === 1) {
            if (!TimerService.loaded) return
            stage = 2
            wait.stop()
            T.eq(TimerService.runs.map(item => item.kind + ":" + item.total), ["timer:300", "focus:900"],
                 "a restart keeps both runs, in the order they end")
            T.eq([TimerService.running, TimerService.kind, TimerService.has("focus"), TimerService.endOf("focus")],
                 [true, "timer", true, seededAt + 900000], "the timer is the one shown; the session runs beside it")
            T.ok(TimerService.remaining > 290000 && TimerService.remaining <= 300000, "about five minutes left")

            T.eq(TimerService.stop(), true, "the chip's stop")
            T.eq([TimerService.runs.map(item => item.kind), root.stoppedKinds], [["focus"], ["timer"]],
                 "stops the one shown and says which")
            T.eq(TimerService.stop("timer"), false, "a kind that does not run stops nothing")
            T.eq([TimerService.start(60), TimerService.startText("2m", "focus"), TimerService.start(0),
                  TimerService.startText("soon")], [true, true, false, false], "started by seconds and by text")
            T.eq(TimerService.runs.map(item => item.kind + ":" + item.total), ["timer:60", "focus:120"],
                 "a new session replaced the old one, the timer is the timer's")
            TimerService.cancel("focus")
            T.eq([TimerService.runs.map(item => item.kind), root.stoppedKinds], [["timer"], ["timer"]],
                 "a cancel goes without a word")
            T.eq(TimerService.describe(), [{ kind: "timer", remaining: 60 }], "`timer get` lists what runs")

            widget.active = true
            const item = widget.item
            T.eq([item.hasData, item.focusRun, TimerService.remainingText], [true, false, "1:00"],
                 "the bar's item shows the timer")
            TimerService.start(300, "focus")
            TimerService.stop("timer")
            T.eq([item.hasData, item.focusRun], [true, true], "and then the session, with Focus's glyph")
            wait.interval = 100
            wait.start()
            return
        }
        if (stage === 2) {
            // The write a turn after the change.
            stage = 3
            wait.stop()
            readBack.path = Paths.stateDir + "/timer.json"
            const kept = JSON.parse(readBack.text())
            T.eq([kept.boot, kept.runs.map(item => item.kind + ":" + item.total)], [boot, ["focus:300"]],
                 "timer.json holds what runs, with the boot")
            TimerService.start(600)
            T.eq([TimerService.kind, TimerService.stopTimer(), TimerService.runs.map(item => item.kind)],
                 ["focus", true, ["focus"]], "\"Timer: stop\" stops the timer, not the session shown for ending first")
            T.eq([TimerService.stopTimer(), root.stoppedKinds.slice(-2)], [true, ["timer", "focus"]],
                 "and the session when no timer runs")
            T.eq([widget.item.hasData, TimerService.running, TimerService.remainingText], [false, false, ""],
                 "nothing runs: the item hides")
            T.finish("TimerServiceTest")
        }
    }

    Component.onCompleted: {
        const runs = L.withRun(L.withRun([], L.run("timer", seededAt + 300000, 300)), L.run("focus", seededAt + 900000, 900))
        seed.setText(L.stateText(runs, boot))
    }
}
