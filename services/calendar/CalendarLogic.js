.pragma library
.import "../appearance/TimeFormat.js" as TimeFormat

// Pure helpers for KDE calendar events delivered by the Plasma calendar
// "pimevents" plugin (Akonadi, including Google accounts added in KDE).

function pad(value) {
    return (value < 10 ? "0" : "") + value
}

function dayKey(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

// Whether the day shown (a dayKey, "" before the first) is no longer the day
// it is at `now`: after a suspend across midnight the calendar's own hour
// clock is late (WallClock.qml), so the service asks this on a jump too.
function dayChanged(shownKey, now) {
    return dayKey(now) !== String(shownKey || "")
}

// What the calendar shows: disabled | sandbox | loading | ok | unavailable.
// Rows mean the calendars are there; no rows after the 15 s wait mean
// Akonadi did not answer. The wait counts for one start of the backend at a
// time: the service clears it when rows arrive and when the backend starts
// again. It used to be cleared only by switching the calendar off and on, so
// once one start had taken longer, every later one (after the five-minute
// cool-down) read "unavailable" until its rows were in.
function status(enabled, sandboxed, rowCount, timedOut) {
    if (!enabled) return "disabled"
    if (sandboxed) return "sandbox"
    if (rowCount > 0) return "ok"
    return timedOut ? "unavailable" : "loading"
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

function validDate(value) {
    return value instanceof Date && !isNaN(value.getTime())
}

// Plasma event data -> { start, end, allDay, title, description, color, type }.
// All-day events report their last day at midnight; they are converted to an
// exclusive end (start of the following day) so range checks stay half-open.
// The same occurrence can arrive twice (shared calendars) and is dropped.
function fromEventData(list) {
    const events = []
    const seen = {}
    for (const data of list || []) {
        if (!data || !validDate(data.startDateTime)) continue
        const allDay = data.isAllDay === true
        const start = allDay ? startOfDay(data.startDateTime) : new Date(data.startDateTime.getTime())
        let end = validDate(data.endDateTime) ? new Date(data.endDateTime.getTime()) : new Date(start.getTime())
        if (allDay) end = addDays(startOfDay(end), 1)
        if (end < start) end = allDay ? addDays(start, 1) : start
        const raw = String(data.title || "")
        const title = raw.trim()
        const color = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(data.eventColor || "") ? data.eventColor : ""
        // The same occurrence arriving twice is the same string twice, so the
        // key uses the title as it came rather than the trimmed one, and it
        // carries the end: without it two untitled events starting at the same
        // minute - which is exactly what a day of back-to-back blocks looks
        // like - collapsed into one row.
        const key = start.getTime() + "|" + end.getTime() + "|" + allDay + "|" + raw + "|" + color
        if (seen[key]) continue
        seen[key] = true
        events.push({
            start: start,
            end: end,
            allDay: allDay,
            title: title.length ? title : "(No title)",
            description: String(data.description || ""),
            color: color,
            type: String(data.eventType || "Event")
        })
    }
    events.sort((a, b) => a.start - b.start || (b.allDay - a.allDay) || a.title.localeCompare(b.title))
    return events
}

// The 42 cells shown by CalendarMonth (Monday first).
function monthRange(year, month) {
    const first = new Date(year, month, 1)
    const offset = (first.getDay() + 6) % 7
    const start = new Date(year, month, 1 - offset)
    return { start: start, end: addDays(start, 42) }
}

function inRange(date, range) {
    return date >= range.start && date < range.end
}

function overlaps(event, from, to) {
    const end = event.end > event.start ? event.end : new Date(event.start.getTime() + 1)
    return event.start < to && end > from
}

function eventsForDay(events, date) {
    const from = startOfDay(date)
    const to = addDays(from, 1)
    return (events || []).filter(event => overlaps(event, from, to))
}

// Next timed event that has not started yet but starts within `minutes`.
function nextUpcoming(events, now, minutes) {
    const limit = now.getTime() + minutes * 60000
    for (const event of events || []) {
        if (event.allDay) continue
        const start = event.start.getTime()
        if (start >= now.getTime() && start <= limit) return event
    }
    return null
}

// Today's events that have not ended yet; all-day events stay all day.
function remainingToday(events, now) {
    return eventsForDay(events, now).filter(event => event.allDay || event.end > now)
}

// "14:00 – 15:00", or "2:00 PM – 3:00 PM" on a 12-hour clock: `twelve` is
// SettingsService.twelveHourClock, which CalendarService.formatRange passes.
// TimeFormat is the one place a time becomes text.
function formatRange(event, twelve) {
    if (event.allDay) return "All day"
    const time = date => TimeFormat.time(date, twelve === true, ":")
    if (event.end <= event.start) return time(event.start)
    return time(event.start) + " – " + time(event.end)
}

// Hidden calendars are stored as a comma separated list of Akonadi collection
// ids in settings.json (settings only hold primitive values).
function parseIdList(text) {
    const seen = {}
    return String(text || "").split(",")
        .map(part => part.trim())
        .filter(part => /^\d+$/.test(part))
        .map(part => Number(part))
        .filter(id => !seen[id] && (seen[id] = true))
}

function formatIdList(ids) {
    return parseIdList((ids || []).join(",")).sort((a, b) => a - b).join(",")
}

function withId(ids, id, present) {
    const list = parseIdList((ids || []).join(",")).filter(item => item !== id)
    if (present) list.push(id)
    return list
}

// Flat descendants rows -> calendars grouped under their account.
// rows: [{ id, name, icon, level, selectable }]
// Colour of an event's bar: the shell accent (default, so the dashboard, the
// notch and the widgets match the rest of the shell) or the calendar's own
// colour, which tells calendars apart. Events without a colour always use the
// accent.
function eventColor(event, accent, mode) {
    const own = event && typeof event.color === "string" ? event.color : ""
    return mode === "calendar" && own.length ? own : accent
}

function groupCalendars(rows) {
    const groups = []
    let current = null
    for (const row of rows || []) {
        if (!row) continue
        if (!row.selectable) {
            current = { id: row.id, name: row.name, icon: row.icon, calendars: [] }
            groups.push(current)
            continue
        }
        if (row.level <= 1 || !current) {
            let local = groups.find(group => group.id === -1)
            if (!local) {
                local = { id: -1, name: "Local", icon: "office-calendar", calendars: [] }
                groups.push(local)
            }
            local.calendars.push(row)
            if (row.level <= 1) current = null
            continue
        }
        current.calendars.push(row)
    }
    return groups.filter(group => group.calendars.length > 0)
}
