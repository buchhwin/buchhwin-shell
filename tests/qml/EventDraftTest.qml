import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/EventDraftLogic.js" as D

ShellRoot {
    function draft(changes) {
        return Object.assign({ title: "Sample event", allDay: false, date: "2026-09-17", endDate: "2026-09-17",
                               start: "14:00", end: "15:30", calendarId: "42", location: "", notes: "" }, changes || {})
    }

    Component.onCompleted: {
        // Parsing
        T.eq(["9", "09", "930", "0930", "9:30", "09.30", "23:59", " 7:05 "].map(D.normalizeTime),
             ["09:00", "09:00", "09:30", "09:30", "09:30", "09:30", "23:59", "07:05"], "time formats")
        T.eq(["24:00", "9:60", "abc", "", "9:5", "12345", "-1"].map(D.parseTime), [null, null, null, null, null, null, null], "invalid times")
        T.eq(D.formatDate(D.parseDate("2026-9-7")), "2026-09-07", "short date parts")
        T.eq([D.parseDate("2026-02-30"), D.parseDate("17.09.2026"), D.parseDate("")], [null, null, null], "invalid dates")
        T.eq(D.shiftDate("2026-12-31", 1), "2027-01-01", "date step across the year")
        T.eq(D.shiftDate("junk", 1), "junk", "invalid date is not shifted")
        T.eq([D.endAfter("09:00", 90), D.endAfter("23:30", 60), D.endAfter("x", 30)], ["10:30", "00:30", ""], "end after a duration wraps midnight")
        T.eq([D.duration("09:00", "10:30"), D.duration("22:00", "01:00"), D.duration("x", "10:00")], [90, 180, -1], "duration")
        T.eq(D.durations.map(D.durationLabel), ["30 min", "1 h", "1.5 h", "2 h"], "quick duration labels")

        // Defaults
        const today = D.defaultDraft(new Date(2026, 8, 17), new Date(2026, 8, 17, 13, 20), 42)
        T.eq([today.date, today.start, today.end, today.calendarId, today.allDay], ["2026-09-17", "14:00", "15:00", "42", false], "today starts at the next full hour")
        T.eq(D.defaultDraft(new Date(2026, 8, 17), new Date(2026, 8, 17, 23, 40), 1).start, "23:00", "late evening clamps to 23:00")
        T.eq(D.defaultDraft(new Date(2026, 8, 20), new Date(2026, 8, 17, 13, 20), "").start, "09:00", "other days start at 09:00")

        // Validation
        T.eq(D.validate(draft()).ok, true, "valid timed draft")
        T.eq(D.validate(draft({ title: "  \n " })).error, "Enter a title.", "title required")
        T.eq(D.validate(draft({ date: "2026-13-01" })).error, "Enter the date as YYYY-MM-DD.", "invalid date")
        T.eq(D.validate(draft({ start: "25:00" })).error, "Enter the start time as HH:MM.", "invalid start")
        T.eq(D.validate(draft({ end: "" })).error, "Enter the end time as HH:MM.", "invalid end")
        T.eq(D.validate(draft({ end: "14:00" })).error, "The event ends when it starts.", "zero length refused")
        T.eq(D.validate(draft({ calendarId: "" })).error, "Choose a calendar.", "calendar required")
        T.eq(D.validate(draft({ calendarId: "0" })).error, "Choose a calendar.", "calendar id 0 refused")
        T.eq(D.validate(draft({ calendarId: "12; rm" })).error, "Choose a calendar.", "non-numeric calendar id refused")
        const night = D.validate(draft({ start: "22:00", end: "01:30" }))
        T.eq([night.ok, night.overnight, night.endDate], [true, true, "2026-09-18"], "end before start is the next day")
        T.eq(D.validate(draft({ allDay: true, start: "junk", endDate: "2026-09-19" })).endDate, "2026-09-19", "all-day ignores times")
        T.eq(D.validate(draft({ allDay: true, endDate: "2026-09-16" })).error, "The end date is before the start date.", "all-day end before start")

        // The request the helper reads from stdin
        const noRule = { repeat: "", weekday: "", count: 0, until: "" }
        T.eq(D.addPayload(draft({ start: "9:5x" }), noRule), null, "invalid draft gives no request")
        T.eq(D.addPayload(draft({ title: " Team call ", start: "930", end: "10:15" }), noRule),
             { collection: 42, title: "Team call", allDay: false, day: "2026-09-17", endDay: "2026-09-17",
               start: "09:30", end: "10:15", location: "", notes: "",
               repeat: "", weekday: "", count: 0, until: "" }, "timed event")
        T.eq(D.addPayload(draft({ start: "23:00", end: "00:30", location: "Room\n2", notes: "Bring notes" }), noRule).endDay,
             "2026-09-18", "an overnight event ends the next day")
        T.eq(D.addPayload(draft({ start: "23:00", end: "00:30", location: "Room\n2" }), noRule).location,
             "Room 2", "a location is one line")
        const allDay = D.addPayload(draft({ allDay: true, date: "2026-9-20", endDate: "2026-09-22" }), noRule)
        T.eq([allDay.day, allDay.endDay, allDay.start, allDay.end], ["2026-09-20", "2026-09-22", "", ""],
             "all-day event: no times, the last day it covers")
        T.eq(D.addPayload(draft(), { repeat: "weekly", weekday: "TH", count: 3, until: "" }).repeat, "weekly",
             "the rule fields travel with the draft")
        T.eq(D.addPayload(draft({ title: "--delete --uid x" }), noRule).title, "--delete --uid x",
             "an option-like title is a value, not an argument")

        // The helper's answer
        T.eq(D.parseAnswer(0, '{"ok": true, "uid": "x"}', ""), { ok: true, message: "", data: { ok: true, uid: "x" } }, "success")
        T.eq(D.parseAnswer(1, '{"ok": false, "error": "This calendar cannot be written to."}').message,
             "This calendar cannot be written to.", "the helper's own message is shown")
        T.eq(D.parseAnswer(1, "", "The event could not be saved.").message, "The event could not be saved.",
             "no answer falls back")
        T.eq(D.parseAnswer(1, "not json", "Fallback.").message, "Fallback.", "unparsable answer falls back")
        T.eq(D.parseAnswer(0, 'warning\n{"ok": true}').ok, true, "the last line is the answer")
        T.eq(D.parseAnswer(127, "").message, "The calendar helper is missing.", "missing helper")
        T.ok(D.parseAnswer(1, '{"ok": false, "error": "no"}', "Secret title failed").message.indexOf("Secret") < 0,
             "a fallback is only used when there is no answer")

        // Calendar choices
        const groups = [
            { id: -1, name: "Local", calendars: [{ id: 2, name: "Birthdays" }, { id: 8, name: "Personal" }] },
            { id: 9, name: "Work account", calendars: [{ id: 21, name: "Holidays" }, { id: 23, name: "Personal" }, { id: 24, name: "Team" }] }
        ]
        const options = D.calendarOptions(groups, [8, 23, 24], [24])
        T.eq(options, [{ value: "23", label: "Personal · Work account", local: false },
                       { value: "8", label: "Personal · Local", local: true },
                       { value: "24", label: "Team · Work account (hidden)", local: false }],
             "account calendars first, local ones after them, hidden last, always labelled with the account")
        T.eq(D.calendarOptions(groups, [], []), [], "no writable calendars")
        const twins = [{ id: -1, name: "Local", calendars: [{ id: 44, name: "Personal" }, { id: 56, name: "Personal" }] }]
        T.eq(D.calendarOptions(twins, [44, 56], []).map(option => option.label), ["Personal · Local", "Personal · Local (2)"], "identical labels numbered")
        T.eq([D.chooseCalendar(options, "23"), D.chooseCalendar(options, "99"), D.chooseCalendar([], "8")], ["23", "23", ""], "remembered calendar, else the first account calendar")
        T.eq([D.calendarIsLocal(options, "8"), D.calendarIsLocal(options, "23"), D.calendarIsLocal(options, "99"), D.calendarIsLocal([], "8")],
             [true, false, false, false], "a local calendar is recognised")
        T.finish("EventDraftTest")
    }
}
