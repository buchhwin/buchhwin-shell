import Quickshell
import QtQuick
import "Harness.js" as T
import "../../services/dashboard/EventDateLogic.js" as Dates
import "../../services/calendar/EventDraftLogic.js" as Draft

// The event editor's From and Until dates: what a typed or stepped From date
// does to the end. The editor's own handlers are replayed here as it runs
// them - the From field's text handler, then whatever the button sets after
// it - because the bugs were in how the two met, not in either alone.
ShellRoot {
    // The editor's state: the draft and the last day the From field read as.
    function editor(date, endDate) {
        return { draft: { allDay: true, date: date, endDate: endDate }, followed: Dates.dayOf(date) }
    }
    // dateField.onTextChanged: the end follows, and its field writes it back.
    function typeDate(state, text) {
        const next = Dates.withDate(state.draft, text, state.followed)
        state.followed = next.followed
        state.draft = Object.assign({}, state.draft, { date: next.date, endDate: next.endDate })
    }
    // Typing one key at a time over a selected (replaced) date.
    function typeOver(state, text) {
        for (let index = 1; index <= text.length; ++index) typeDate(state, text.slice(0, index))
    }
    // The Previous/Next day buttons: the From field first (its handler runs at
    // once), then the end the shift asked for.
    function step(state, days) {
        const next = Dates.shiftDay(state.draft, days)
        typeDate(state, next.date)
        state.draft = Object.assign({}, state.draft, { endDate: next.endDate })
    }
    function shown(state) { return [state.draft.date, state.draft.endDate] }
    function valid(state) {
        return Draft.validate(Object.assign({ title: "Sample event", calendarId: "42" }, state.draft)).ok
    }

    Component.onCompleted: {
        // ---- what a text reads as -------------------------------------------
        T.eq(Dates.dayOf("2026-10-5"), "2026-10-05", "a short day reads as its day")
        T.eq([Dates.dayOf("2"), Dates.dayOf("2026-10-"), Dates.dayOf(""), Dates.dayOf("2026-02-30")],
             ["", "", "", ""], "a text on its way to a date reads as none")

        // ---- Previous day and Next day --------------------------------------
        T.eq(Dates.shiftDay({ date: "2026-10-19", endDate: "2026-10-19" }, -1),
             { date: "2026-10-18", endDate: "2026-10-18" }, "a one-day event moves back as one day")
        T.eq(Dates.shiftDay({ date: "2026-10-19", endDate: "2026-10-21" }, 1),
             { date: "2026-10-20", endDate: "2026-10-22" }, "a longer one keeps its length")
        T.eq(Dates.shiftDay({ date: "2026-12-31", endDate: "2026-12-31" }, 1),
             { date: "2027-01-01", endDate: "2027-01-01" }, "across the year")
        T.eq(Dates.shiftDay({ date: "2026-10-", endDate: "2026-10-19" }, 1),
             { date: "2026-10-", endDate: "2026-10-19" }, "an unreadable date moves nothing")
        T.eq(Dates.shiftDay({ date: "2026-10-19", endDate: "x" }, 1),
             { date: "2026-10-20", endDate: "x" }, "an unreadable end stays as typed")

        // As the editor runs them: before, Previous day left the end before the
        // start (Save disabled) and Next day made a two-day event of one.
        const back = editor("2026-10-19", "2026-10-19")
        step(back, -1)
        T.eq(shown(back), ["2026-10-18", "2026-10-18"], "Previous day: still one day")
        T.ok(valid(back), "and it can be saved")
        const ahead = editor("2026-10-19", "2026-10-19")
        step(ahead, 1)
        step(ahead, 1)
        T.eq(shown(ahead), ["2026-10-21", "2026-10-21"], "Next day twice: still one day")
        const longer = editor("2026-10-19", "2026-10-21")
        step(longer, 1)
        T.eq(shown(longer), ["2026-10-20", "2026-10-22"], "a three-day event steps by a day and keeps three")
        step(longer, -2)
        T.eq(shown(longer), ["2026-10-18", "2026-10-20"], "and back")
        const nextDay = editor("2026-10-19", "2026-10-20")
        step(nextDay, 1)
        T.eq(shown(nextDay), ["2026-10-20", "2026-10-21"], "a two-day event whose end is the next start keeps two days")

        // ---- typing a date ---------------------------------------------------
        const typed = editor("2026-10-05", "2026-10-05")
        typeOver(typed, "2026-10-19")
        T.eq(shown(typed), ["2026-10-19", "2026-10-19"], "typed over the selection, key by key: the end follows")
        T.ok(valid(typed), "and the event can be saved")

        // Only the day retyped: "2026-10-1" reads as the 1st on the way.
        const day = editor("2026-10-05", "2026-10-05")
        typeDate(day, "2026-10-0")
        typeDate(day, "2026-10-")
        typeDate(day, "2026-10-1")
        T.eq(shown(day), ["2026-10-1", "2026-10-01"], "the 1st on the way takes the end along")
        typeDate(day, "2026-10-19")
        T.eq(shown(day), ["2026-10-19", "2026-10-19"], "and the 19th takes it on from there")

        const pasted = editor("2026-10-05", "2026-10-05")
        typeDate(pasted, "2026-11-02")
        T.eq(shown(pasted), ["2026-11-02", "2026-11-02"], "a pasted date")

        // A longer event is not cut to one day by a new start.
        const multi = editor("2026-10-05", "2026-10-07")
        typeOver(multi, "2026-10-06")
        T.eq(shown(multi), ["2026-10-06", "2026-10-07"], "a longer event's end stays where it is")

        // A timed event's hidden end follows too, so switching All day on
        // afterwards does not find the end on the old day.
        const timed = { draft: { allDay: false, date: "2026-10-05", endDate: "2026-10-05" }, followed: "2026-10-05" }
        typeOver(timed, "2026-10-20")
        T.eq(timed.draft.endDate, "2026-10-20", "a timed event's end date follows its date")

        // Nothing read yet (a field filled from nothing): nothing to follow.
        T.eq(Dates.withDate({ endDate: "2026-10-05" }, "2026-10-09", ""),
             { date: "2026-10-09", endDate: "2026-10-05", followed: "2026-10-09" },
             "without a day read before, the end is left alone")
        T.eq(Dates.withDate({ endDate: "2026-10-05" }, "2026-1", "2026-10-05"),
             { date: "2026-1", endDate: "2026-10-05", followed: "2026-10-05" },
             "a text that is no date keeps the last day it was")

        T.finish("EventDateTest")
    }
}
