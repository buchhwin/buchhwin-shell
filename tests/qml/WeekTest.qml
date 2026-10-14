import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/WeekLogic.js" as W

ShellRoot {
    function key(date) { return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate() }

    Component.onCompleted: {
        // Week start (Monday first)
        T.eq(key(W.weekStart(new Date(2026, 8, 17))), "2026-9-14", "Thursday → Monday")
        T.eq(key(W.weekStart(new Date(2026, 8, 14))), "2026-9-14", "Monday stays")
        T.eq(key(W.weekStart(new Date(2026, 8, 20, 23, 30))), "2026-9-14", "Sunday late evening → previous Monday")
        T.eq(key(W.weekStart(new Date(2026, 8, 17), 0)), "2026-9-13", "Sunday-first weeks")
        T.eq(key(W.weekStart(new Date(2026, 9, 2))), "2026-9-28", "week across a month change")
        T.eq(key(W.addDays(new Date(2026, 11, 31), 1)), "2027-1-1", "a day across the year end")
        T.eq(W.addDays(new Date(2026, 9, 24), 2).getHours(), 0, "days stay at midnight across the DST change")

        // Preview sample
        const monday = new Date(2026, 8, 14)
        const sample = W.sampleEvents(new Date(2026, 8, 17), ["c1", "c2", "c3", "c4"])
        T.eq([sample.length, sample.filter(event => event.allDay).length], [11, 2], "sample week: eleven events, two of them all-day")
        T.ok(sample.every(event => event.start >= monday), "the sample starts in the week of the date")
        T.eq(sample.filter(event => !event.allDay && key(event.start) === "2026-9-14").length, 3, "three timed events on Monday, two overlapping")
        T.ok(sample.every(event => ["c1", "c2", "c3", "c4"].indexOf(event.color) >= 0), "sample colours from the caller")
        T.finish("WeekTest")
    }
}
