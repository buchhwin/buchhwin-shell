import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/appearance/TimeFormat.js" as F

// The one place a time is turned into text. Nine `Qt.formatTime(date, "HH:mm")`
// calls in six files meant the shell could only ever show 24 hours whatever
// its locale said - the date followed the locale, the time did not. "What does
// en_US do with 18:52" is arithmetic, which is exactly what a nested session
// cannot answer and a test can.
ShellRoot {
    function at(hour, minute) { return new Date(2026, 8, 21, hour, minute, 0) }

    Component.onCompleted: {
        // ---- hours ------------------------------------------------------

        T.eq(F.hour(at(18, 52), false), "18", "24-hour evening")
        T.eq(F.hour(at(6, 52), false), "06", "24-hour keeps the leading zero")
        T.eq(F.hour(at(18, 52), true), "6", "12-hour evening")
        T.eq(F.hour(at(6, 52), true), "6", "12-hour morning")
        // The two that are always wrong when somebody writes this by hand.
        T.eq(F.hour(at(0, 5), true), "12", "midnight is 12, not 0")
        T.eq(F.hour(at(12, 5), true), "12", "noon is 12, not 0")
        T.eq(F.hour(at(0, 5), false), "00", "and midnight is 00 on a 24-hour clock")
        // A leading zero on a 12-hour clock is how nobody writes it, and a
        // column of 24-hour times has to line up - so the two differ on purpose.
        T.eq(F.hour(at(9, 0), true), "9", "12-hour drops the leading zero")
        T.eq(F.hour(at(9, 0), false), "09", "24-hour does not")

        // ---- minutes ----------------------------------------------------

        T.eq(F.minute(at(18, 5)), "05", "minutes always keep the zero")
        T.eq(F.minute(at(18, 52)), "52", "and are otherwise themselves")
        T.eq(F.minute(at(18, 0)), "00", "on the hour")

        // ---- the suffix -------------------------------------------------

        T.eq(F.suffix(at(6, 0), true), "AM", "morning")
        T.eq(F.suffix(at(18, 0), true), "PM", "evening")
        T.eq(F.suffix(at(0, 0), true), "AM", "midnight is AM")
        T.eq(F.suffix(at(12, 0), true), "PM", "noon is PM")
        // Empty rather than absent, so a caller can append it unconditionally.
        T.eq(F.suffix(at(18, 0), false), "", "a 24-hour clock has none")

        // ---- the whole time ---------------------------------------------

        T.eq(F.time(at(18, 52), false, ":"), "18:52", "24-hour")
        T.eq(F.time(at(18, 52), true, ":"), "6:52 PM", "12-hour")
        T.eq(F.time(at(6, 5), true, ":"), "6:05 AM", "12-hour morning, padded minutes")
        // The clock widget spaces its colon at its largest size, and the
        // separator has to survive that.
        T.eq(F.time(at(18, 52), false, " : "), "18 : 52", "a spaced separator")
        T.eq(F.time(at(18, 52), false), "18:52", "the separator defaults to a colon")

        // ---- an hour on its own, for the weather strip -------------------

        T.eq(F.hourLabel(at(14, 0), false), "14", "24-hour strip")
        T.eq(F.hourLabel(at(14, 0), true), "2 PM", "12-hour strip carries the suffix")
        T.eq(F.hourLabel(at(0, 0), true), "12 AM", "and midnight reads right")

        T.finish("TimeFormatTest")
    }
}
