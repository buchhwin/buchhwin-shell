pragma Singleton
import Quickshell
import QtQuick
import "system/WallClockLogic.js" as Logic
import "lock/LockLogic.js" as LockLogic

// "The wall clock jumped": after a suspend, and when the time is set. Qt's
// timers run on the monotonic clock, which stands still while the machine
// sleeps, and Quickshell's SystemClock arms one timer for its next boundary
// and does nothing on a resume (0.3.x). After a night in suspend an hour clock
// ticked up to 59 minutes late and a minute clock up to one: yesterday's
// "today" in the calendar and the clock's event hint, the forecast of the
// evening before, the lock screen showing the time the lid was shut.
//
// Every SystemClock binds `enabled` to `ticking`. A jump turns it off and on
// again, which arms each clock anew from the time it is now, and `jumped`
// tells the services that keep a day or a fetch time of their own.
//
// Two ways to hear of one. IdleService's swayidle calls kick() right after a
// resume. And a timer here compares the wall clock with its own monotonic
// ticks: that catches the time being set, a session without swayidle, and the
// lock screen's process, which runs no swayidle of its own and is the first
// thing a resume shows - it looks every 5 s there, every minute in the shell.
Singleton {
    id: root

    property bool ticking: true
    signal jumped()

    readonly property bool lockProcess: LockLogic.lockProcess(Quickshell)
    // The wall clock at the last tick (or kick), in ms.
    property double lastWall: Date.now()

    function kick() {
        ticking = false
        ticking = true
        lastWall = Date.now()
        // A full step from now: the tick due soon would otherwise read the
        // short way since the kick as a jump of its own.
        detector.restart()
        jumped()
    }

    Timer {
        id: detector
        interval: root.lockProcess ? 5000 : 60000
        repeat: true
        running: true
        onTriggered: {
            const now = Date.now()
            const moved = Logic.jumped(root.lastWall, now, interval)
            root.lastWall = now
            if (moved) root.kick()
        }
    }
}
