import Quickshell
import Quickshell.Io
import QtQuick
import "Harness.js" as T
import "../../services/calendar/CalendarLogic.js" as C

ShellRoot {
    FileView { id: fixture; path: Qt.resolvedUrl("../fixtures/plasma-calendar-events.json").toString().replace("file://", ""); blockLoading: true }

    // The plugin hands over JS Dates; the fixture stores local ISO strings.
    function localDate(text) {
        const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/.exec(text || "")
        return match ? new Date(+match[1], +match[2] - 1, +match[3], +match[4], +match[5], +match[6]) : new Date(NaN)
    }

    Component.onCompleted: {
        const raw = JSON.parse(fixture.text()).events.map(item => Object.assign({}, item, {
            startDateTime: localDate(item.startDateTime), endDateTime: localDate(item.endDateTime) }))
        const events = C.fromEventData(raw)
        T.eq(events.length, 6, "duplicate and invalid events dropped")
        T.eq(events.map(event => event.title), ["(No title)", "Nachtfahrt", "Feiertag Beispiel", "Team-Standup", "Zahnarzt, Kontrolle", "Urlaub"], "sorted by start, titles trimmed")
        const dentist = events.find(event => event.title === "Zahnarzt, Kontrolle")
        T.eq([dentist.start.getHours(), dentist.end.getHours(), dentist.allDay], [14, 15, false], "timed event")
        T.eq(dentist.color, "", "invalid colour dropped")
        T.eq(events.find(event => event.title === "Team-Standup").color, "#9fe1e7", "calendar colour kept")
        const holiday = events.find(event => event.title === "Urlaub")
        T.ok(holiday.allDay, "all-day event")
        T.eq(C.dayKey(holiday.end), "2026-03-15", "all-day end becomes exclusive")
        T.eq(C.dayKey(events.find(event => event.title === "Feiertag Beispiel").end), "2026-03-11", "single all-day event lasts one day")
        T.eq(C.fromEventData(null).length, 0, "no data")

        // Two untitled events one after the other. They used to become one
        // row: the key carried neither the end nor anything that told them
        // apart, which is what a day of back-to-back blocks looks like.
        const blocks = C.fromEventData([
            { startDateTime: new Date(2026, 2, 10, 9, 0, 0), endDateTime: new Date(2026, 2, 10, 9, 30, 0) },
            { startDateTime: new Date(2026, 2, 10, 9, 0, 0), endDateTime: new Date(2026, 2, 10, 10, 0, 0) }
        ])
        T.eq(blocks.length, 2, "two untitled events at the same minute are two events")
        // The same occurrence from two shared calendars is still one row.
        const shared = C.fromEventData([
            { title: "Team-Standup", startDateTime: new Date(2026, 2, 10, 9, 0, 0), endDateTime: new Date(2026, 2, 10, 9, 15, 0) },
            { title: "Team-Standup", startDateTime: new Date(2026, 2, 10, 9, 0, 0), endDateTime: new Date(2026, 2, 10, 9, 15, 0) }
        ])
        T.eq(shared.length, 1, "and the same one from two calendars is still one")

        const day = new Date(2026, 2, 10)
        T.eq(C.eventsForDay(events, day).map(event => event.title), ["Nachtfahrt", "Feiertag Beispiel", "Team-Standup", "Zahnarzt, Kontrolle"], "events of a day include multi-day events")
        T.eq(C.eventsForDay(events, new Date(2026, 2, 11)).map(event => event.title), ["Nachtfahrt"], "overnight event on its last day")
        T.eq(C.eventsForDay(events, new Date(2026, 2, 15)).length, 0, "exclusive all-day end")

        T.eq(C.nextUpcoming(events, new Date(2026, 2, 10, 8, 50), 15).title, "Team-Standup", "event within the hint window")
        T.eq(C.nextUpcoming(events, new Date(2026, 2, 10, 8, 30), 15), null, "event outside the hint window")
        T.eq(C.nextUpcoming(events, new Date(2026, 2, 10, 9, 5), 15), null, "running events are not upcoming")
        T.eq(C.remainingToday(events, new Date(2026, 2, 10, 12, 0)).map(event => event.title), ["Nachtfahrt", "Feiertag Beispiel", "Zahnarzt, Kontrolle"], "finished events drop out")

        const range = C.monthRange(2026, 2)
        T.eq([C.dayKey(range.start), C.dayKey(range.end)], ["2026-02-23", "2026-04-06"], "March 2026 grid range")
        T.eq(C.dayKey(C.monthRange(2026, 5).start), "2026-06-01", "month starting on Monday")
        T.ok(C.inRange(new Date(2026, 1, 23), range) && !C.inRange(new Date(2026, 3, 6), range), "grid range is half-open")

        T.eq(C.formatRange(dentist), "14:00 – 15:00", "time range")
        T.eq(C.formatRange(holiday), "All day", "all-day label")

        // Hidden calendar ids
        T.eq(C.parseIdList(" 20, 19,x,20,,7 "), [20, 19, 7], "id list parsing ignores junk and duplicates")
        T.eq(C.formatIdList([20, 7, 20]), "7,20", "id list formatting")
        T.eq(C.withId([7, 20], 20, false), [7], "remove id")
        T.eq(C.withId([7], 20, true), [7, 20], "add id")

        // Calendar tree grouping
        const groups = C.groupCalendars([
            { id: 2, name: "Geburtstage", icon: "view-calendar-birthday", level: 1, selectable: true },
            { id: 9, name: "Konto", icon: "account-google", level: 1, selectable: false },
            { id: 21, name: "Feiertage", icon: "view-calendar", level: 2, selectable: true },
            { id: 23, name: "Privat", icon: "view-calendar", level: 2, selectable: true },
            { id: 8, name: "Persönlich", icon: "office-calendar", level: 1, selectable: true },
            { id: 30, name: "Leeres Konto", icon: "folder", level: 1, selectable: false }
        ])
        T.eq(groups.map(group => group.name + ":" + group.calendars.map(item => item.id).join("+")), ["Local:2+8", "Konto:21+23"], "calendars grouped by account, empty groups dropped")
        // Event bar colour: accent by default, the calendar's own colour on request.
        const colored = { color: "#ff8800" }
        const plain = { color: "" }
        T.eq([C.eventColor(colored, "#50e2cb", "accent"), C.eventColor(colored, "#50e2cb", "calendar"),
              C.eventColor(plain, "#50e2cb", "calendar"), C.eventColor(null, "#50e2cb", "calendar")],
             ["#50e2cb", "#ff8800", "#50e2cb", "#50e2cb"], "event colour follows the setting")
        T.finish("CalendarTest")
    }
}
