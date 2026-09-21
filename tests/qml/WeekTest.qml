import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/WeekLogic.js" as W

ShellRoot {
    // Synthetic events in the shape of CalendarLogic.fromEventData.
    function ev(title, start, end, allDay) {
        return { title: title, start: start, end: end, allDay: allDay === true, color: "", description: "", type: "Event" }
    }
    function at(day, hours, minutes) { return new Date(2026, 8, day, hours, minutes || 0) }
    function key(date) { return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate() }

    Component.onCompleted: {
        // Week start (Monday first)
        T.eq(key(W.weekStart(new Date(2026, 8, 17))), "2026-9-14", "Thursday → Monday")
        T.eq(key(W.weekStart(new Date(2026, 8, 14))), "2026-9-14", "Monday stays")
        T.eq(key(W.weekStart(new Date(2026, 8, 20, 23, 30))), "2026-9-14", "Sunday late evening → previous Monday")
        T.eq(key(W.weekStart(new Date(2026, 8, 17), 0)), "2026-9-13", "Sunday-first weeks")
        T.eq(key(W.weekStart(new Date(2026, 9, 2))), "2026-9-28", "week across a month change")
        T.eq(W.weekDays(new Date(2026, 11, 28)).map(key), ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-1-1", "2027-1-2", "2027-1-3"], "seven days across the year end")
        T.eq(W.weekDays(new Date(2026, 9, 19)).map(date => date.getHours()), [0, 0, 0, 0, 0, 0, 0], "days stay at midnight across the DST change")
        T.eq(key(W.shiftWeek(new Date(2026, 8, 17), 1)), "2026-9-24", "next week keeps the weekday")
        T.eq(key(W.shiftWeek(new Date(2026, 8, 3), -1)), "2026-8-27", "previous week across a month")
        const monday = new Date(2026, 8, 14)
        T.eq([W.dayIndex(monday, new Date(2026, 8, 13)), W.dayIndex(monday, at(16, 12)), W.dayIndex(monday, new Date(2026, 8, 21))], [-1, 2, 7], "day index inside and outside the week")

        // Merging per-day lists
        const multi = ev("trip", new Date(2026, 8, 15), new Date(2026, 8, 18), true)
        const call = ev("call", at(15, 9), at(15, 10))
        const merged = W.uniqueEvents([[multi, call], [ev("trip", new Date(2026, 8, 15), new Date(2026, 8, 18), true)], [multi], null])
        T.eq(merged.map(event => event.title), ["trip", "call"], "duplicates from several days merged, longer first on ties")

        // All-day row
        T.ok(W.inAllDayRow(multi), "all-day event in the all-day row")
        T.ok(W.inAllDayRow(ev("night shift", at(15, 20), at(16, 20))), "24-hour timed event in the all-day row")
        T.ok(!W.inAllDayRow(ev("overnight", at(15, 22), at(16, 6))), "shorter overnight event stays timed")
        const allDay = W.allDayLayout([
            multi,
            ev("holiday", new Date(2026, 8, 16), new Date(2026, 8, 17), true),
            ev("friday", new Date(2026, 8, 18), new Date(2026, 8, 19), true),
            ev("long", new Date(2026, 8, 10), new Date(2026, 8, 16), true),
            ev("next week", new Date(2026, 8, 20), new Date(2026, 8, 23), true),
            ev("outside", new Date(2026, 8, 21), new Date(2026, 8, 22), true),
            ev("conference", at(17, 8), at(19, 18)),
            call
        ], monday)
        const byTitle = title => allDay.items.find(item => item.event.title === title)
        T.eq(allDay.items.length, 6, "events outside the week and short timed events skipped")
        T.eq([byTitle("long").column, byTitle("long").span, byTitle("long").lane, byTitle("long").continuesBefore], [0, 2, 0, true], "event from last week clipped to Monday")
        T.eq([byTitle("trip").column, byTitle("trip").span, byTitle("trip").lane], [1, 3, 1], "multi-day event spans its days in the next free lane")
        T.eq([byTitle("holiday").column, byTitle("holiday").span, byTitle("holiday").lane], [2, 1, 0], "single day reuses the first lane after the long event ended")
        T.eq([byTitle("friday").column, byTitle("friday").lane], [4, 1], "lane reused after the trip ended (exclusive end)")
        T.eq([byTitle("conference").column, byTitle("conference").span], [3, 3], "timed three-day event covers Thu–Sat")
        T.eq([byTitle("next week").column, byTitle("next week").span, byTitle("next week").continuesAfter], [6, 1, true], "event into next week clipped to Sunday")
        T.eq(allDay.lanes, 2, "lane count")
        T.eq(W.allDayLayout([], monday).lanes, 0, "no all-day events")

        // Timed blocks
        const blocks = W.dayBlocks([
            ev("a", at(15, 9), at(15, 10)),
            ev("b", at(15, 9, 30), at(15, 11)),
            ev("c", at(15, 10), at(15, 10, 30)),
            ev("d", at(15, 11), at(15, 12)),
            ev("reminder", at(15, 14), at(15, 14)),
            ev("overnight", at(14, 22), at(15, 1, 30)),
            multi,
            ev("tomorrow", at(16, 9), at(16, 10))
        ], at(15, 12), 30)
        const block = title => blocks.find(item => item.event.title === title)
        T.eq(blocks.map(item => item.event.title), ["overnight", "a", "b", "c", "d", "reminder"], "timed events of the day only, sorted")
        T.eq([block("overnight").start, block("overnight").end, block("overnight").continuesBefore], [0, 90, true], "event from the previous evening clipped to midnight")
        T.eq([block("a").column, block("a").columns], [0, 2], "a shares the width with b")
        T.eq([block("b").column, block("b").columns], [1, 2], "b next to a")
        T.eq([block("c").column, block("c").columns], [0, 2], "c takes a's column after a ended")
        T.eq([block("d").column, block("d").columns], [0, 1], "d starts when b ends: full width")
        T.eq([block("reminder").start, block("reminder").end, block("reminder").shownEnd], [840, 840, 870], "zero-length event drawn with the minimum height")
        const late = W.dayBlocks([ev("late", at(15, 23, 50), at(16, 0, 20))], at(15, 0), 30)
        T.eq([late[0].start, late[0].end, late[0].shownEnd, late[0].continuesAfter], [1410, 1440, 1440, true], "late event moved up to stay inside the day")
        const short = W.dayBlocks([ev("x", at(15, 9), at(15, 9, 10)), ev("y", at(15, 9, 20), at(15, 10))], at(15, 0), 30)
        T.eq(short.map(item => item.columns), [2, 2], "minimum height counts for overlaps")
        const triple = W.dayBlocks([ev("p", at(15, 8), at(15, 12)), ev("q", at(15, 9), at(15, 10)), ev("r", at(15, 9), at(15, 10, 15)), ev("s", at(15, 10), at(15, 11))], at(15, 0), 30)
        T.eq(triple.map(item => item.event.title + item.column + "/" + item.columns), ["p0/3", "r1/3", "q2/3", "s2/3"], "three columns in one group, longer first")
        const dst = W.dayBlocks([ev("dst", new Date(2026, 9, 25, 9), new Date(2026, 9, 25, 10))], new Date(2026, 9, 25), 30)
        T.eq([dst[0].start, dst[0].end], [540, 600], "wall-clock minutes on a DST day")

        // Preview sample
        const sample = W.sampleEvents(new Date(2026, 8, 17), ["c1", "c2", "c3", "c4"])
        T.eq([sample.length, W.allDayLayout(sample, monday).items.length], [11, 2], "sample week: eleven events, two in the all-day row")
        T.eq(W.dayBlocks(sample, monday, 30).map(item => item.columns), [2, 2, 1], "sample Monday overlaps")
        T.ok(sample.every(event => ["c1", "c2", "c3", "c4"].indexOf(event.color) >= 0), "sample colours from the caller")

        // Day view: ranges one day wide
        const wednesday = new Date(2026, 8, 16, 18, 45)
        T.eq(key(W.rangeStart(wednesday, 1)), "2026-9-16", "one-day range starts on the day itself")
        T.eq(W.rangeStart(wednesday, 1).getHours(), 0, "one-day range starts at midnight")
        T.eq(key(W.rangeStart(wednesday, 7, 1)), "2026-9-14", "seven-day range starts on Monday")
        T.eq(W.weekDays(W.rangeStart(wednesday, 1), 1).map(key), ["2026-9-16"], "a single day in the range")
        T.eq([key(W.shiftRange(wednesday, 1, 1)), key(W.shiftRange(wednesday, -1, 1))], ["2026-9-17", "2026-9-15"], "day arrows move one day")
        T.eq(key(W.shiftRange(new Date(2026, 8, 1), -1, 1)), "2026-8-31", "previous day across a month")
        T.eq(key(W.shiftRange(wednesday, 1, 7)), "2026-9-23", "week arrows still move seven days")
        const day = new Date(2026, 8, 16)
        T.eq([W.dayIndex(day, at(15, 12), 1), W.dayIndex(day, at(16, 12), 1), W.dayIndex(day, at(17, 12), 1)], [-1, 0, 1], "day index of a one-day range")
        const dayAllDay = W.allDayLayout([
            multi,
            ev("holiday", new Date(2026, 8, 16), new Date(2026, 8, 17), true),
            ev("other day", new Date(2026, 8, 18), new Date(2026, 8, 19), true),
            call
        ], day, 1)
        const dayItem = title => dayAllDay.items.find(item => item.event.title === title)
        T.eq(dayAllDay.items.map(item => item.event.title), ["trip", "holiday"], "only the day's all-day events")
        T.eq([dayItem("trip").column, dayItem("trip").span, dayItem("trip").continuesBefore, dayItem("trip").continuesAfter], [0, 1, true, true], "multi-day event clipped to the single column")
        T.eq([dayItem("holiday").column, dayItem("holiday").span, dayItem("holiday").lane], [0, 1, 1], "second all-day event takes the next lane")
        T.eq(dayAllDay.lanes, 2, "lane count of a one-day range")

        // Scroll position
        T.eq(W.scrollHour([blocks, []], 7), 7, "default 7:00 when events start later (continuing events ignored)")
        T.eq(W.scrollHour([W.dayBlocks([ev("early", at(16, 5, 45), at(16, 6, 30))], at(16, 0), 30)], 7), 5, "earlier event moves the scroll position")
        T.eq(W.scrollHour([], 7), 7, "empty week")
        T.finish("WeekTest")
    }
}
