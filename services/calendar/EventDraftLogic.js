.pragma library

// Pure helpers for the new-event dialog: time/date parsing, validation, the
// request scripts/calendar-helper.py reads from stdin, its answer and the
// calendar choices. Nothing here runs a process, and a title never reaches an
// argument: the helper is given one JSON object on standard input.

function pad(value) {
    return (value < 10 ? "0" : "") + value
}

function formatDate(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function formatTime(hours, minutes) {
    return pad(hours) + ":" + pad(minutes)
}

// "YYYY-MM-DD" → local Date, or null for anything else (also 2026-02-30).
function parseDate(text) {
    const match = /^\s*(\d{4})-(\d{1,2})-(\d{1,2})\s*$/.exec(String(text || ""))
    if (!match) return null
    const date = new Date(+match[1], +match[2] - 1, +match[3])
    return date.getFullYear() === +match[1] && date.getMonth() === +match[2] - 1 && date.getDate() === +match[3]
        ? date : null
}

// Accepts "9", "09", "930", "0930", "9:30", "09.30" → { hours, minutes } or null.
function parseTime(text) {
    const value = String(text || "").trim()
    let match = /^(\d{1,2})(?:[:.](\d{2}))?$/.exec(value)
    if (!match) match = /^(\d{1,2})(\d{2})$/.exec(value)
    if (!match) return null
    const hours = +match[1]
    const minutes = match[2] === undefined ? 0 : +match[2]
    return hours <= 23 && minutes <= 59 ? { hours: hours, minutes: minutes } : null
}

function normalizeTime(text) {
    const time = parseTime(text)
    return time ? formatTime(time.hours, time.minutes) : String(text || "")
}

function shiftDate(text, days) {
    const date = parseDate(text)
    if (!date) return String(text || "")
    return formatDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days))
}

function minutesOf(time) {
    return time.hours * 60 + time.minutes
}

// End time `minutes` after the start (wraps past midnight).
function endAfter(startText, minutes) {
    const time = parseTime(startText)
    if (!time) return ""
    const total = ((minutesOf(time) + minutes) % 1440 + 1440) % 1440
    return formatTime(Math.floor(total / 60), total % 60)
}

// Minutes from start to end; an end before the start is on the next day.
function duration(startText, endText) {
    const start = parseTime(startText)
    const end = parseTime(endText)
    if (!start || !end) return -1
    const minutes = minutesOf(end) - minutesOf(start)
    return minutes < 0 ? minutes + 1440 : minutes
}

// Draft for `day`: the next full hour when it is today, else 09:00; one hour.
function defaultDraft(day, now, calendarId) {
    const isToday = formatDate(day) === formatDate(now)
    const hour = isToday ? Math.min(23, now.getHours() + 1) : 9
    const start = formatTime(hour, 0)
    return {
        title: "",
        allDay: false,
        date: formatDate(day),
        endDate: formatDate(day),
        start: start,
        end: endAfter(start, 60),
        calendarId: String(calendarId || ""),
        location: "",
        notes: ""
    }
}

function singleLine(text) {
    return String(text || "").replace(/[\r\n\t]+/g, " ").trim()
}

// → { ok, error, overnight, endDate }. endDate is the real last date (the
// next day for a timed event that ends after midnight).
function validate(draft) {
    const fail = message => ({ ok: false, error: message, overnight: false, endDate: "" })
    if (!draft) return fail("Nothing to save.")
    if (!singleLine(draft.title).length) return fail("Enter a title.")
    const date = parseDate(draft.date)
    if (!date) return fail("Enter the date as YYYY-MM-DD.")
    if (!/^[1-9]\d{0,18}$/.test(String(draft.calendarId || ""))) return fail("Choose a calendar.")
    if (draft.allDay) {
        const endDate = parseDate(draft.endDate)
        if (!endDate) return fail("Enter the end date as YYYY-MM-DD.")
        if (endDate < date) return fail("The end date is before the start date.")
        return { ok: true, error: "", overnight: false, endDate: formatDate(endDate) }
    }
    const start = parseTime(draft.start)
    const end = parseTime(draft.end)
    if (!start) return fail("Enter the start time as HH:MM.")
    if (!end) return fail("Enter the end time as HH:MM.")
    if (minutesOf(start) === minutesOf(end)) return fail("The event ends when it starts.")
    const overnight = minutesOf(end) < minutesOf(start)
    return { ok: true, error: "", overnight: overnight, endDate: overnight ? shiftDate(draft.date, 1) : formatDate(date) }
}

// The request for `calendar-helper.py add`, or null when the draft is invalid.
// The helper builds the RRULE itself from repeat/weekday/count/until, so the
// rule grammar exists exactly once (scripts/lib/ical.py).
function addPayload(draft, rule) {
    const check = validate(draft)
    if (!check.ok) return null
    const payload = {
        collection: Number(draft.calendarId),
        title: singleLine(draft.title),
        allDay: draft.allDay === true,
        day: formatDate(parseDate(draft.date)),
        endDay: check.endDate,
        start: draft.allDay ? "" : normalizeTime(draft.start),
        end: draft.allDay ? "" : normalizeTime(draft.end),
        location: singleLine(draft.location),
        notes: String(draft.notes || "").trim()
    }
    return Object.assign(payload, rule || { repeat: "", weekday: "", count: 0, until: "" })
}

// The helper prints one JSON object and exits non-zero when it failed. Its
// messages are written for the panel, so they are shown as they are; a reason
// is a short token the caller turns into its own sentence.
function parseAnswer(exitCode, output, fallback) {
    const text = String(output || "").trim()
    if (exitCode === 127) return { ok: false, message: "The calendar helper is missing.", data: null }
    let data = null
    try {
        data = JSON.parse(text.split("\n").filter(line => line.trim().length).pop() || "")
    } catch (error) {
        data = null
    }
    if (!data || typeof data !== "object")
        return { ok: false, message: fallback || "The calendar did not answer.", data: null }
    if (data.ok) return { ok: true, message: "", data: data }
    return { ok: false, message: String(data.error || "") || fallback || "The calendar refused the change.",
             data: data }
}

// Calendar choices for new events: writable calendars from the grouped
// calendar list (CalendarLogic.groupCalendars). The account is appended when
// names repeat; hidden calendars stay choosable but are marked.
function calendarOptions(groups, writableIds, hiddenIds) {
    const writable = (writableIds || []).map(Number)
    const hidden = (hiddenIds || []).map(Number)
    const rows = []
    for (const group of groups || [])
        for (const calendar of group.calendars || [])
            if (writable.indexOf(Number(calendar.id)) >= 0) rows.push({ calendar: calendar, group: group })
    // Calendars of an account come first: a local file only lives on this
    // computer, and picking it by accident means the phone never sees the
    // event. Hidden calendars stay at the end.
    const rank = row => (hidden.indexOf(Number(row.calendar.id)) >= 0 ? 2 : 0) + (Number(row.group.id) === -1 ? 1 : 0)
    const sorted = rows.map((row, index) => ({ row: row, index: index }))
        .sort((a, b) => rank(a.row) - rank(b.row) || a.index - b.index)
        .map(entry => entry.row)
    const seen = {}
    return sorted.map(row => {
        // The account (or "Local") is always part of the label, so the target
        // is never a guess.
        const base = row.calendar.name + " · " + row.group.name
        seen[base] = (seen[base] || 0) + 1
        return {
            value: String(row.calendar.id),
            label: base + (seen[base] > 1 ? " (" + seen[base] + ")" : "")
                + (hidden.indexOf(Number(row.calendar.id)) >= 0 ? " (hidden)" : ""),
            local: Number(row.group.id) === -1
        }
    })
}

// True when the chosen calendar is a local file (no account syncs it).
function calendarIsLocal(options, value) {
    const option = (options || []).find(entry => entry.value === String(value || ""))
    return option ? option.local === true : false
}

// The remembered calendar when it is still offered, else the first choice.
function chooseCalendar(options, preferred) {
    const list = options || []
    const wanted = String(preferred || "")
    if (wanted.length && list.some(option => option.value === wanted)) return wanted
    return list.length ? list[0].value : ""
}

// Quick durations offered next to the time fields (minutes).
const durations = [30, 60, 90, 120]

function durationLabel(minutes) {
    if (minutes < 60) return minutes + " min"
    return (minutes / 60).toString() + " h"
}
