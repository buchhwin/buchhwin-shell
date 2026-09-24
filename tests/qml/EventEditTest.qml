import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/calendar/EventEditLogic.js" as E
import "../../services/calendar/RecurrenceLogic.js" as R

// The CSV fixtures are gone with konsolekalendar: an event is now resolved by
// scripts/calendar-helper.py, which answers with one JSON object. What is
// tested here is what the shell makes of that answer and what it sends back.
ShellRoot {
    function at(day, hours, minutes) { return new Date(2026, 2, day, hours, minutes || 0) }
    function timed(title, day, h1, m1, h2, m2) {
        return { title: title, start: at(day, h1, m1), end: at(day, h2, m2), allDay: false, description: "" }
    }
    function allDay(title, day, days) {
        return { title: title, start: at(day, 0), end: at(day + days, 0), allDay: true, description: "" }
    }
    function answer(data) { return { ok: true, message: "", data: Object.assign({ ok: true }, data) } }

    readonly property var single: {
        "ok": true, "uid": "single@example.invalid", "item": 11, "masterItem": 11, "exceptionItem": 0,
        "collection": 8, "writable": true, "allDay": false, "location": "Room 2, north",
        "description": "Notes", "recurs": false, "isOccurrence": false, "isException": false,
        "recurrenceId": "", "rrule": "", "repeat": "", "weekday": "", "count": 0, "until": "", "ruleKnown": true
    }
    readonly property var series: {
        "ok": true, "uid": "series@example.invalid", "item": 20, "masterItem": 20, "exceptionItem": 0,
        "collection": 8, "writable": true, "allDay": false, "location": "", "description": "",
        "recurs": true, "isOccurrence": true, "isException": false, "recurrenceId": "20260310T080000",
        "rrule": "FREQ=WEEKLY;BYDAY=TU", "repeat": "weekly", "weekday": "TU", "count": 0, "until": "",
        "ruleKnown": true
    }
    readonly property var exception: {
        "ok": true, "uid": "series@example.invalid", "item": 21, "masterItem": 20, "exceptionItem": 21,
        "collection": 8, "writable": true, "allDay": false, "location": "", "description": "",
        "recurs": false, "isOccurrence": false, "isException": true, "recurrenceId": "20260310T080000",
        "rrule": "", "repeat": "", "weekday": "", "count": 0, "until": "", "ruleKnown": true
    }

    Component.onCompleted: {
        // ---- the request that identifies a shown occurrence ----------------
        T.eq(E.resolveRequest(timed("Review \"Q1\", draft", 10, 14, 0, 15, 30)),
             { day: "2026-03-10", start: "14:00", allDay: false, title: "Review \"Q1\", draft" }, "resolve request")
        T.eq(E.resolveRequest(allDay("Vacation", 10, 3)).start, "", "an all-day event has no time")
        T.eq(E.resolveRequest(null), null, "no event, no request")
        T.eq(E.resolveRequest({ title: "x", start: new Date(NaN), allDay: false }), null, "an invalid date is refused")

        // ---- what the helper's answer means --------------------------------
        const found = E.applyResolve(answer(single))
        T.eq([found.ok, found.item, found.location, found.recurs], [true, 11, "Room 2, north", false], "a single event")
        const occurrence = E.applyResolve(answer(series))
        T.eq([occurrence.recurs, occurrence.isOccurrence, occurrence.masterItem, occurrence.recurrenceId],
             [true, true, 20, "20260310T080000"], "one occurrence of a series")
        const moved = E.applyResolve(answer(exception))
        T.eq([moved.recurs, moved.isException, moved.item, moved.masterItem], [true, true, 21, 20],
             "a changed occurrence knows its series")
        T.eq(E.applyResolve({ ok: false, message: "", data: { ok: false, reason: "ambiguous" } }).reason, "ambiguous",
             "the helper's reason is kept")
        T.eq(E.applyResolve(answer(Object.assign({}, single, { writable: false }))).reason, "readOnly",
             "a read-only calendar is refused before anything is offered")
        T.eq(E.applyResolve(null).reason, "unavailable", "no answer at all")
        T.ok(E.applyResolve({ ok: false, message: "", data: { ok: false, reason: "notFound" } }).message.length > 0,
             "every refusal says something")

        T.eq(E.previewMatch({ title: "Lunch break", start: at(10, 12), sampleLocation: "Cafeteria" }).location,
             "Cafeteria", "preview sample")
        T.eq(E.previewMatch({ title: "Standup", start: at(10, 9), sampleRecurring: true }).recurs, true,
             "the flagged preview sample is a series")
        T.eq(E.previewMatch({ title: "Standup", start: at(10, 9), sampleRecurring: true }).repeat, "weekly",
             "and it says how it repeats")

        // ---- drafts and changes ---------------------------------------------
        const event = Object.assign(timed("Review \"Q1\", draft", 10, 14, 0, 15, 30), { description: " Notes\nline 2 " })
        const original = E.draftFor(event, "Room 2, north")
        T.eq([original.title, original.date, original.start, original.end, original.allDay, original.location, original.notes],
             ["Review \"Q1\", draft", "2026-03-10", "14:00", "15:30", false, "Room 2, north", "Notes\nline 2"], "timed draft")
        const vacation = E.draftFor(allDay("Vacation sample", 10, 3), "")
        T.eq([vacation.date, vacation.endDate, vacation.allDay], ["2026-03-10", "2026-03-12", true],
             "all-day draft has an inclusive end")
        T.eq(E.draftFor(timed("(No title)", 10, 18, 0, 18, 30), "").title, "", "untitled draft")

        const edit = changes => Object.assign({}, original, changes)
        const noRule = R.emptyDraft(event.start)
        T.eq(E.changes(original, edit({ title: "A", notes: "B" }), noRule, noRule), ["title", "notes"], "changed field names")
        T.eq(E.changes(original, edit({}), noRule, { repeat: "daily", ending: "never", count: 0, until: "" }),
             ["repeat"], "a changed repetition counts as a change")
        T.eq(E.validate(edit({ end: "25:00" }), original, false, noRule).error, "Enter the end time as HH:MM.",
             "changed times are validated")
        T.eq(E.validate(edit({}), original, false, { repeat: "weekly", ending: "count", count: 0, until: "" }).error,
             "Repeat between 1 and 999 times.", "the repetition is validated too")

        const trip = { title: "Night train", start: at(10, 22), end: at(12, 8), allDay: false, description: "" }
        T.eq([E.timesLocked(trip), E.timesLocked(event), E.timesLocked(allDay("Vacation sample", 10, 3))],
             [true, false, false], "times locked for day-long timed events")
        const tripDraft = E.draftFor(trip, "")
        T.eq(E.validate(Object.assign({}, tripDraft, { start: "07:00" }), tripDraft, true, noRule).error,
             "Change the times of multi-day events in Merkuro.", "locked times refused")

        // ---- which command a change takes ------------------------------------
        T.eq(E.changeCommand(found, "single"), "modify", "an event that does not repeat is just modified")
        T.eq(E.changeCommand(occurrence, "single"), "occurrence", "one occurrence becomes its own incidence")
        T.eq(E.changeCommand(occurrence, "series"), "modify", "the whole series is modified")
        T.eq(E.changeCommand(moved, "single"), "modify", "a changed occurrence already is its own incidence")
        T.eq(E.changeCommand(E.refuse("notFound"), "single"), "", "an unresolved event has no command")

        // ---- the requests ----------------------------------------------------
        T.eq(E.changeRequest(original, edit({}), found, false, noRule, noRule, "single"), null, "nothing changed")
        const renamed = E.changeRequest(original, edit({ title: "New title" }), found, false, noRule, noRule, "single")
        T.eq([renamed.command, renamed.request.item, renamed.request.changes.title], ["modify", 11, "New title"],
             "only the title is sent")
        T.eq(renamed.request.changes.day, undefined, "untouched times are not sent")
        const retimed = E.changeRequest(original, edit({ start: "930", end: "10:00" }), found, false, noRule, noRule, "single")
        T.eq([retimed.request.changes.day, retimed.request.changes.start, retimed.request.changes.end],
             ["2026-03-10", "09:30", "10:00"], "new times")
        T.eq(E.changeRequest(original, edit({ start: "23:00", end: "01:00" }), found, false, noRule, noRule, "single")
              .request.changes.endDay, "2026-03-11", "an overnight event ends the next day")
        const madeAllDay = E.changeRequest(original, edit({ allDay: true, endDate: "2026-03-11" }), found, false, noRule, noRule, "single")
        T.eq([madeAllDay.request.changes.allDay, madeAllDay.request.changes.start], [true, ""], "timed to all-day")

        const movedOne = E.changeRequest(original, edit({ start: "11:00", end: "12:00" }), occurrence, false, noRule, noRule, "single")
        T.eq([movedOne.command, movedOne.request.item, movedOne.request.recurrenceId],
             ["occurrence", 20, "20260310T080000"], "one occurrence is written against its series")
        const weekly = { repeat: "weekly", weekday: "TU", ending: "never", count: 0, until: "" }
        const everyDay = { repeat: "daily", weekday: "", ending: "count", count: 5, until: "" }
        const rerule = E.changeRequest(original, edit({}), occurrence, false, weekly, everyDay, "series")
        T.eq([rerule.command, rerule.request.changes.repeat, rerule.request.changes.count],
             ["modify", "daily", 5], "the series' repetition changes with the series")
        T.eq(E.changeRequest(original, edit({ title: "x" }), occurrence, false, weekly, everyDay, "single")
              .request.changes.repeat, undefined, "one occurrence never changes the rule")

        T.eq(E.deleteRequest(found, "single"), { command: "delete", request: { item: 11 } }, "delete a single event")
        T.eq(E.deleteRequest(occurrence, "series"), { command: "delete", request: { item: 20 } }, "delete the whole series")
        T.eq(E.deleteRequest(occurrence, "single"),
             { command: "exclude", request: { item: 20, recurrenceId: "20260310T080000", exception: 0 } },
             "drop one occurrence")
        T.eq(E.deleteRequest(moved, "single").request.exception, 21,
             "dropping a moved occurrence removes the moved copy as well")
        T.eq(E.deleteRequest(E.refuse("notFound"), "single"), null, "an unresolved event cannot be deleted")

        T.eq([E.wroteMessage("delete"), E.wroteMessage("modify")], ["Event deleted.", "Event updated."],
             "what the panel says after a write")

        // ---- the panel copies its arguments ----------------------------------
        T.eq(E.sameEvent(event, Object.assign({}, event)), true, "a copy is the same event")
        T.eq(E.sameEvent(event, timed("Review \"Q1\", draft", 10, 14, 0, 16, 0)), false, "a different end is not")

        T.finish("EventEditTest")
    }
}
