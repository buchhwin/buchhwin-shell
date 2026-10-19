.pragma library
.import "../calendar/EventDraftLogic.js" as Draft

// How the event editor's From date takes its Until date along. Both fields
// hold what was typed, so these rules work on text, and on the last day the
// From field could be read as: while a date is typed over, the field's text
// is no date at all for most of the keys.

// The day a text reads as, "YYYY-MM-DD", or "" while it reads as none.
function dayOf(text) {
    const date = Draft.parseDate(text)
    return date ? Draft.formatDate(date) : ""
}

// A new text in the From field. `followed` is the last day the field could
// be read as. An end on that day moves to the new day with it, so a one-day
// event stays one day however its date is typed. Compared as raw texts, as
// the editor once did, the end stopped following at the first key typed over
// the selected date ("2" is no date, and its end was no longer "the same"),
// and "2026-10-1" on the way to the 19th read as the 1st, took the end there
// and left it. Any other end - a longer event, or one being typed - stays.
// → { date, endDate, followed }
function withDate(draft, text, followed) {
    const date = String(text === undefined || text === null ? "" : text)
    const endDate = String(draft && draft.endDate || "")
    const last = String(followed || "")
    const day = dayOf(date)
    if (!day.length) return { date: date, endDate: endDate, followed: last }
    const follows = last.length > 0 && dayOf(endDate) === last
    return { date: date, endDate: follows ? day : endDate, followed: day }
}

// Previous day and Next day move the whole event: a one-day event stays one
// day and a longer one keeps its length. The buttons used to shift the end
// themselves after the From field had already taken a following end along,
// so it moved twice - "Previous day" put a one-day event's end before its
// start, "Next day" made it two days long. An unreadable From date moves
// nothing, and an unreadable end stays as it was typed.
// → { date, endDate }
function shiftDay(draft, days) {
    const date = String(draft && draft.date || "")
    const endDate = String(draft && draft.endDate || "")
    if (!dayOf(date).length) return { date: date, endDate: endDate }
    return { date: Draft.shiftDate(date, days),
             endDate: dayOf(endDate).length ? Draft.shiftDate(endDate, days) : endDate }
}
