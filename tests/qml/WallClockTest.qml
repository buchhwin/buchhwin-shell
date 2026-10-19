import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/system/WallClockLogic.js" as W
import "../../services/calendar/CalendarLogic.js" as C

// When the wall clock counts as jumped (WallClock.qml re-arms every
// SystemClock then), and when the calendar's day has changed under it. The
// re-arming itself was checked with a clock shim (CLOCK_REALTIME moved by
// 9 h, the monotonic clock untouched, as a resume leaves them): both an hour
// and a minute clock showed the new time within one detector step.
ShellRoot {
    Component.onCompleted: {
        const minute = 60000
        const t = 1760000000000
        T.ok(!W.jumped(t, t + minute, minute), "one step on both clocks: no jump")
        T.ok(!W.jumped(t, t + minute + 20000, minute), "a tick 20 s late (a busy moment) is no jump")
        T.ok(!W.jumped(t, t + minute - 400, minute), "an NTP nudge is no jump")
        T.ok(W.jumped(t, t + minute + 8.5 * 3600000, minute), "a night in suspend between two ticks is one")
        T.ok(W.jumped(t, t + minute + 31000, minute), "half a minute more than the step is one")
        T.ok(W.jumped(t, t - 3600000, minute), "the time set back an hour is one")
        // The lock screen's process looks every 5 s; the slack is never below 5 s.
        T.ok(!W.jumped(t, t + 5000 + 4000, 5000), "the 5-s step: 4 s late is no jump")
        T.ok(W.jumped(t, t + 5000 + 6000, 5000), "a suspend of a few seconds is one")

        // The calendar's day after a jump.
        const evening = new Date(2026, 9, 18, 23, 30)
        const key = C.dayKey(evening)
        T.ok(C.dayChanged(key, new Date(2026, 9, 19, 8, 0)), "lid shut at 23:30, opened at 8:00: a new day")
        T.ok(!C.dayChanged(key, new Date(2026, 9, 18, 23, 55)), "the same evening: the same day")
        T.ok(C.dayChanged("", evening), "no day shown yet counts as changed")
        T.finish("WallClockTest")
    }
}
