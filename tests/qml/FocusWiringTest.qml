//@ pragma ShellId buchhwin-shell-lock
import Quickshell
import QtQuick
import qs.services
import "Harness.js" as T

// A Focus session across the real services: AdaptiveService.focusFor turns
// Focus on with its own Do Not Disturb (NotificationService.dndBy "focus")
// and a "focus" run in TimerService; the run's end turns Focus and the Do Not
// Disturb off, stopping the run ends Focus, ending Focus drops the run, and a
// timer beside it is left alone. Under the lock screen's shell id, so no
// notification server runs (pitfall 82) - and TimerService, which keeps and
// announces nothing there (`sessionSide`), still counts down and says when a
// run ended, which is all this needs.
ShellRoot {
    id: root
    property int stage: 0
    property int tries: 0

    Timer {
        id: wait
        interval: 50
        repeat: true
        running: true
        onTriggered: root.advance()
    }

    function advance() {
        tries += 1
        if (stage === 0) {
            if ((!NotificationService.stateLoaded || !TimerService.loaded) && tries < 200) return
            stage = 1
            T.ok(NotificationService.stateLoaded && TimerService.loaded, "the state is read in the sandbox")
            T.eq(NotificationService.server, null, "and no server runs")
            NotificationService.setDnd("off")

            // Stopping the countdown ends Focus.
            T.eq(AdaptiveService.focusFor(600), true, "a session of ten minutes")
            T.eq([AdaptiveService.focusActive, NotificationService.dndActive, NotificationService.dndBy,
                  TimerService.has("focus"), AdaptiveService.focusSession], [true, true, "focus", true, true],
                 "Focus, its own Do Not Disturb and the countdown")
            T.ok(AdaptiveService.focusLabel.indexOf("\u2192 ") === 0, "the tile says when it ends: " + AdaptiveService.focusLabel)
            TimerService.stop()
            T.eq([AdaptiveService.focusActive, NotificationService.dndActive, TimerService.running], [false, false, false],
                 "stopping the countdown ended Focus and its Do Not Disturb")

            // Ending Focus drops the countdown, a timer beside it runs on.
            AdaptiveService.focusFor(600)
            TimerService.start(300)
            AdaptiveService.setFocus(false)
            T.eq([AdaptiveService.focusActive, TimerService.has("focus"), TimerService.has("timer"), AdaptiveService.focusLabel],
                 [false, false, true, "Off"], "Focus off by hand: its countdown goes, the timer stays")
            TimerService.stop("timer")
            T.eq(AdaptiveService.focusForText("soon"), false, "a duration that is none starts nothing")
            T.eq(AdaptiveService.focusActive, false, "and does not turn Focus on")

            // The end, on time.
            T.eq(AdaptiveService.focusForText("1s"), true, "a session of one second")
            tries = 0
            return
        }
        if (stage === 1) {
            if (TimerService.has("focus") && tries < 100) return
            stage = 2
            wait.stop()
            T.eq([AdaptiveService.focusActive, NotificationService.dndActive, NotificationService.dndBy, TimerService.running],
                 [false, false, "", false], "its end turned Focus off, and the Do Not Disturb Focus owned with it")
            T.finish("FocusWiringTest")
        }
    }
}
