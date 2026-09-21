.pragma library
.import "EventDraftLogic.js" as Draft
.import "RecurrenceLogic.js" as Rec

// Pure helpers for editing and deleting existing events.
//
// The Plasma calendar plugin exposes no UID, so an event from the dashboard is
// sent to scripts/calendar-helper.py, which looks it up in Akonadi by day,
// title, all-day flag and - for a series - time of day, and answers with the
// stored incidence: its item, its calendar, whether it recurs, and which
// occurrence was meant. A series is no longer refused: the helper can change
// or drop a single occurrence as well as the whole series.
//
// Nothing here runs a process, and a title never leaves these objects.

function normalize(text) {
    return String(text || "").replace(/\s+/g, " ").trim()
}

// The dashboard shows empty titles as "(No title)".
function sameTitle(eventTitle, summary) {
    const wanted = normalize(eventTitle)
    const actual = normalize(summary)
    return actual === wanted || (actual === "" && wanted === "(No title)")
}

// Local day keys the event covers (the Plasma event end is exclusive).
function lastDay(event) {
    const start = event.start
    const end = event.end
    if (event.allDay) {
        const last = new Date(end.getFullYear(), end.getMonth(), end.getDate() - 1)
        return last < start ? Draft.formatDate(start) : Draft.formatDate(last)
    }
    if (end <= start) return Draft.formatDate(start)
    return Draft.formatDate(new Date(end.getTime() - 1))
}

const messages = {
    notFound: "This event was not found in the KDE calendars. Refresh and try again, or use Merkuro.",
    ambiguous: "Several events match this one. Edit or delete it in Merkuro.",
    readOnly: "This calendar is read-only. Change the event where it comes from.",
    unsure: "This event could not be matched safely. Edit or delete it in Merkuro.",
    unavailable: "The calendars could not be read."
}

function refuse(reason) {
    return { ok: false, reason: reason, message: messages[reason] || messages.unsure,
             uid: "", location: "", item: 0 }
}

// ---- resolving --------------------------------------------------------------

// What the helper needs to find the shown occurrence again.
function resolveRequest(event) {
    if (!event || !(event.start instanceof Date) || isNaN(event.start)) return null
    return {
        day: Draft.formatDate(event.start),
        start: event.allDay ? "" : Draft.formatTime(event.start.getHours(), event.start.getMinutes()),
        allDay: event.allDay === true,
        title: normalize(event.title)
    }
}

// The helper's answer as the identity the panel works with.
function applyResolve(answer) {
    if (!answer || !answer.data) return refuse("unavailable")
    const data = answer.data
    if (!data.ok) return refuse(String(data.reason || "unsure"))
    if (data.writable === false) return refuse("readOnly")
    return {
        ok: true, reason: "", message: "",
        uid: String(data.uid || ""),
        item: Number(data.item) || 0,
        masterItem: Number(data.masterItem) || 0,
        exceptionItem: Number(data.exceptionItem) || 0,
        collection: Number(data.collection) || 0,
        location: String(data.location || ""),
        notes: String(data.description || ""),
        recurs: data.recurs === true || data.isException === true,
        isOccurrence: data.isOccurrence === true,
        isException: data.isException === true,
        recurrenceId: String(data.recurrenceId || ""),
        repeat: String(data.repeat || ""),
        weekday: String(data.weekday || ""),
        count: Number(data.count) || 0,
        until: String(data.until || ""),
        ruleKnown: data.ruleKnown !== false
    }
}

// Synthetic events of `calendar preview` (WeekLogic.sampleEvents): no process,
// a made-up identity; the flagged sample behaves like a weekly series.
function previewMatch(event) {
    if (!event || !(event.start instanceof Date)) return refuse("notFound")
    const slug = normalize(event.title).toLowerCase().replace(/[^a-z0-9]+/g, "-")
    const series = event.sampleRecurring === true
    return {
        ok: true, reason: "", message: "",
        uid: "preview-" + slug + "@example.invalid",
        item: 1, masterItem: 1, exceptionItem: 0, collection: 1,
        location: String(event.sampleLocation || ""), notes: "",
        recurs: series, isOccurrence: series, isException: false,
        recurrenceId: series ? Draft.formatDate(event.start).replace(/-/g, "") + "T090000" : "",
        repeat: series ? "weekly" : "", weekday: series ? Rec.weekdayOf(event.start) : "",
        count: 0, until: "", ruleKnown: true
    }
}

// The panel copies its arguments, so the event object in the dialog is not the
// one the identity check ran on: compare what makes an event unique instead.
function sameEvent(a, b) {
    if (!a || !b) return false
    const time = value => value instanceof Date ? value.getTime() : Number(value) || 0
    return time(a.start) === time(b.start) && time(a.end) === time(b.end)
        && a.allDay === b.allDay && normalize(a.title) === normalize(b.title)
}

// ---- edit ------------------------------------------------------------------

// Timed events of a day or longer cannot be shown in the editor's
// date + start/end fields: their times stay as they are.
function timesLocked(event) {
    if (!event || event.allDay) return false
    return event.end.getTime() - event.start.getTime() >= 24 * 3600 * 1000
}

// Editor draft for an existing event (same shape as Draft.defaultDraft).
function draftFor(event, location) {
    const start = event.start
    const end = event.end
    const allDay = event.allDay === true
    return {
        title: event.title === "(No title)" ? "" : String(event.title || ""),
        allDay: allDay,
        date: Draft.formatDate(start),
        endDate: lastDay(event),
        start: allDay ? "09:00" : Draft.formatTime(start.getHours(), start.getMinutes()),
        end: allDay ? "10:00" : Draft.formatTime(end.getHours(), end.getMinutes()),
        calendarId: "",
        location: String(location || ""),
        notes: String(event.description || "").trim()
    }
}

// Like Draft.validate without the calendar (it cannot move). Unchanged times
// of a timed event are not sent, so they are not checked either (events
// without duration or longer than a day keep theirs).
function validate(draft, original, locked, rule) {
    const fail = message => ({ ok: false, error: message, overnight: false, endDate: "" })
    if (!draft) return fail("Nothing to save.")
    const repeat = Rec.validate(rule, draft.date)
    if (!repeat.ok) return fail(repeat.error)
    const moved = timingChanged(original, draft)
    if (locked && moved) return fail("Change the times of multi-day events in Merkuro.")
    if (!moved && !draft.allDay) {
        if (!Draft.singleLine(draft.title).length) return fail("Enter a title.")
        return { ok: true, error: "", overnight: false, endDate: "" }
    }
    return Draft.validate(Object.assign({}, draft, { calendarId: "1" }))
}

function timingChanged(original, draft) {
    if (!original || !draft) return false
    if (draft.allDay !== original.allDay) return true
    if (Draft.formatDate(Draft.parseDate(draft.date) || new Date(NaN)) !== original.date) return true
    if (draft.allDay) return Draft.formatDate(Draft.parseDate(draft.endDate) || new Date(NaN)) !== original.endDate
    return Draft.normalizeTime(draft.start) !== original.start || Draft.normalizeTime(draft.end) !== original.end
}

// → names of the changed fields (title, time, location, notes, repeat).
function changes(original, draft, originalRule, rule) {
    const list = []
    if (!original || !draft) return list
    if (Draft.singleLine(draft.title) !== Draft.singleLine(original.title)) list.push("title")
    if (timingChanged(original, draft)) list.push("time")
    if (Draft.singleLine(draft.location) !== Draft.singleLine(original.location)) list.push("location")
    if (String(draft.notes || "").trim() !== String(original.notes || "").trim()) list.push("notes")
    if (rule && !Rec.sameRule(originalRule, rule)) list.push("repeat")
    return list
}

// ---- the requests the helper reads ------------------------------------------

// Which command changes this event, given what the user chose in the dialog.
// "single" means this one occurrence, "series" the whole thing.
function changeCommand(identity, scope) {
    if (!identity || !identity.ok) return ""
    if (scope !== "single" || !identity.recurs) return "modify"
    return identity.isException ? "modify" : "occurrence"
}

// The request for that command, or null when nothing changed or it is invalid.
function changeRequest(original, draft, identity, locked, originalRule, rule, scope) {
    const command = changeCommand(identity, scope)
    if (!command) return null
    const check = validate(draft, original, locked, rule)
    if (!check.ok) return null
    const changed = changes(original, draft, originalRule, rule)
    if (!changed.length) return null
    const given = {}
    if (changed.indexOf("title") >= 0) given.title = Draft.singleLine(draft.title)
    if (changed.indexOf("location") >= 0) given.location = Draft.singleLine(draft.location)
    if (changed.indexOf("notes") >= 0) given.notes = String(draft.notes || "").trim()
    if (changed.indexOf("time") >= 0 || draft.allDay) {
        given.allDay = draft.allDay === true
        given.day = Draft.formatDate(Draft.parseDate(draft.date))
        given.endDay = check.endDate || given.day
        given.start = draft.allDay ? "" : Draft.normalizeTime(draft.start)
        given.end = draft.allDay ? "" : Draft.normalizeTime(draft.end)
    }
    // A single occurrence keeps the series' rule; only the series itself can
    // change how often it repeats.
    if (changed.indexOf("repeat") >= 0 && command !== "occurrence")
        Object.assign(given, Rec.payload(rule))
    const request = {
        item: command === "occurrence" ? identity.masterItem || identity.item : identity.item,
        allDay: draft.allDay === true,
        day: Draft.formatDate(Draft.parseDate(draft.date)),
        changes: given
    }
    if (command === "occurrence") request.recurrenceId = identity.recurrenceId
    return { command: command, request: request }
}

// Deleting: the whole event, or just this occurrence of a series.
function deleteRequest(identity, scope) {
    if (!identity || !identity.ok) return null
    if (scope === "single" && identity.recurs) {
        if (!identity.masterItem || !identity.recurrenceId) return null
        return { command: "exclude", request: { item: identity.masterItem,
                                                recurrenceId: identity.recurrenceId,
                                                exception: identity.exceptionItem || 0 } }
    }
    // The whole series is the master incidence; deleting it takes its changed
    // occurrences with it.
    return { command: "delete", request: { item: identity.masterItem || identity.item } }
}

// What the panel says after a write, so the wording is in one place.
function wroteMessage(kind, scope, single) {
    if (kind === "delete") return scope === "single" && !single ? "Event deleted." : "Event deleted."
    return "Event updated."
}
