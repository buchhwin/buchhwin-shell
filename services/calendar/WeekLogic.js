.pragma library

// Pure layout for the dashboard week and day views: range start, the all-day
// row with lanes for multi-day events and time-positioned blocks for timed
// events, placed side by side when they overlap. Events are the objects
// produced by CalendarLogic.fromEventData ({ start, end, allDay, title, color,
// … }; all-day ends are exclusive).
// A range is `dayCount` days wide: 7 for the week view, 1 for the day view.

const dayMs = 86400000

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

// Whole days between two dates' midnights (DST safe).
function daysBetween(from, to) {
    return Math.round((startOfDay(to) - startOfDay(from)) / dayMs)
}

// First day of the week containing `date`; firstDay 0 = Sunday, 1 = Monday.
function weekStart(date, firstDay) {
    const first = firstDay === undefined ? 1 : firstDay
    return addDays(date, -((date.getDay() - first + 7) % 7))
}

function weekDays(start, dayCount) {
    const count = dayCount === undefined ? 7 : dayCount
    const days = []
    for (let i = 0; i < count; ++i) days.push(addDays(start, i))
    return days
}

// First day of the shown range: the day itself for one-day ranges, otherwise
// the first day of its week.
function rangeStart(date, dayCount, firstDay) {
    return dayCount === 1 ? startOfDay(date) : weekStart(date, firstDay)
}

// The same weekday in the week `weeks` weeks later (arrows move by week).
function shiftWeek(date, weeks) {
    return addDays(date, 7 * weeks)
}

// Arrows move by the width of the shown range (one week or one day).
function shiftRange(date, steps, dayCount) {
    return addDays(date, (dayCount === undefined ? 7 : dayCount) * steps)
}

// Position of `date` in the range starting at `start` (-1 before it, `dayCount`
// after it).
function dayIndex(start, date, dayCount) {
    const count = dayCount === undefined ? 7 : dayCount
    const index = daysBetween(start, date)
    return index < 0 ? -1 : index > count - 1 ? count : index
}

function eventKey(event) {
    return event.start.getTime() + "|" + event.end.getTime() + "|" + event.allDay + "|" + event.title + "|" + event.color
}

// The per-day lists of CalendarService.eventsFor() repeat multi-day events;
// merge them into one list, earliest first and longer events first on ties.
function uniqueEvents(lists) {
    const seen = {}
    const result = []
    for (const list of lists || []) {
        for (const event of list || []) {
            if (!event || !(event.start instanceof Date) || !(event.end instanceof Date)) continue
            const key = eventKey(event)
            if (seen[key]) continue
            seen[key] = true
            result.push(event)
        }
    }
    result.sort((a, b) => a.start - b.start || (b.end - b.start) - (a.end - a.start))
    return result
}

// All-day events and timed events of 24 hours or more go to the all-day row.
function inAllDayRow(event) {
    return event.allDay === true || event.end - event.start >= dayMs
}

// Day columns [first, last) of an event inside the range; null when outside.
function columnSpan(event, start, dayCount) {
    const count = dayCount === undefined ? 7 : dayCount
    const first = Math.max(0, daysBetween(start, event.start))
    const endDay = startOfDay(event.end)
    // An end at midnight does not cover that day; zero-length events still take one.
    let last = daysBetween(start, event.end) + (event.end.getTime() === endDay.getTime() ? 0 : 1)
    last = Math.min(count, Math.max(last, daysBetween(start, event.start) + 1))
    if (first >= count || last <= 0 || last <= first) return null
    return { first: first, last: last }
}

// All-day row: { items: [{ event, column, span, lane, continuesBefore,
// continuesAfter }], lanes } with each event in the first free lane.
function allDayLayout(events, start, dayCount) {
    const rangeEnd = addDays(start, dayCount === undefined ? 7 : dayCount)
    const laneEnds = []
    const items = []
    const candidates = (events || []).filter(inAllDayRow).slice()
    candidates.sort((a, b) => a.start - b.start || (b.end - b.start) - (a.end - a.start))
    for (const event of candidates) {
        const span = columnSpan(event, start, dayCount)
        if (!span) continue
        let lane = laneEnds.findIndex(end => end <= span.first)
        if (lane < 0) {
            lane = laneEnds.length
            laneEnds.push(0)
        }
        laneEnds[lane] = span.last
        items.push({
            event: event,
            column: span.first,
            span: span.last - span.first,
            lane: lane,
            continuesBefore: event.start < start,
            continuesAfter: event.end > rangeEnd
        })
    }
    return { items: items, lanes: laneEnds.length }
}

// Minutes after the day's midnight, clipped to 0…1440 (wall clock, DST safe).
function minuteOfDay(date, day) {
    const from = startOfDay(day)
    if (date <= from) return 0
    if (date >= addDays(from, 1)) return 1440
    return date.getHours() * 60 + date.getMinutes()
}

// Timed events of one day as blocks { event, start, end, column, columns,
// continuesBefore, continuesAfter } in minutes. Short events are drawn at least
// `minMinutes` tall, and that height counts for overlaps so blocks never cover
// each other. Overlapping groups share the width in columns.
function dayBlocks(events, day, minMinutes) {
    const from = startOfDay(day)
    const to = addDays(from, 1)
    const minimum = minMinutes === undefined ? 30 : minMinutes
    const blocks = []
    for (const event of events || []) {
        if (inAllDayRow(event)) continue
        const touches = event.end > event.start ? event.start < to && event.end > from
            : event.start >= from && event.start < to
        if (!touches) continue
        const start = minuteOfDay(event.start, from)
        const end = minuteOfDay(event.end, from)
        const shownEnd = Math.min(1440, Math.max(end, start + minimum))
        blocks.push({
            event: event,
            start: Math.min(start, 1440 - minimum),
            end: end,
            shownEnd: shownEnd,
            column: 0,
            columns: 1,
            continuesBefore: event.start < from,
            continuesAfter: event.end > to
        })
    }
    blocks.sort((a, b) => a.start - b.start || b.shownEnd - a.shownEnd)

    let group = []
    let groupEnd = -1
    let columnEnds = []
    const closeGroup = () => {
        for (const block of group) block.columns = columnEnds.length
        group = []
        columnEnds = []
    }
    for (const block of blocks) {
        if (group.length && block.start >= groupEnd) closeGroup()
        let column = columnEnds.findIndex(end => end <= block.start)
        if (column < 0) {
            column = columnEnds.length
            columnEnds.push(0)
        }
        columnEnds[column] = block.shownEnd
        block.column = column
        group.push(block)
        groupEnd = group.length === 1 ? block.shownEnd : Math.max(groupEnd, block.shownEnd)
    }
    closeGroup()
    return blocks
}

// Synthetic events around the week of `date` for `calendar preview`
// (screenshots without private data): overlaps, a multi-day and an overnight
// event, a zero-length reminder. `colors`: four calendar colours.
function sampleEvents(date, colors) {
    const monday = weekStart(date, 1)
    const at = (day, hours, minutes) => new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + day, hours, minutes || 0)
    const make = (title, start, end, allDay, color, extra) => Object.assign({ title: title, start: start, end: end, allDay: allDay, color: color, description: "Sample event for screenshots.", type: "Event" }, extra || {})
    const palette = colors || []
    const blue = palette[0] || "", green = palette[1] || "", orange = palette[2] || "", purple = palette[3] || ""
    return [
        make("Conference", addDays(monday, 1), addDays(monday, 4), true, purple),
        make("Holiday", addDays(monday, 5), addDays(monday, 6), true, green),
        make("Team standup", at(0, 9), at(0, 9, 30), false, blue, { sampleRecurring: true }),
        make("Design review", at(0, 9, 15), at(0, 10, 45), false, orange),
        make("Lunch", at(0, 12), at(0, 13), false, green, { sampleLocation: "Cafeteria" }),
        make("Focus time", at(1, 8), at(1, 11), false, blue),
        make("Call", at(1, 9), at(1, 10), false, orange),
        make("Reminder", at(2, 14), at(2, 14), false, purple),
        make("Workshop", at(3, 10), at(3, 16), false, blue),
        make("Night train", at(4, 22), at(5, 6, 30), false, orange),
        make("Run", at(6, 7, 30), at(6, 8, 30), false, green)
    ]
}

// Hour the time grid scrolls to: the default (7:00) unless an event of the
// week starts earlier.
function scrollHour(dayBlockLists, defaultHour) {
    let hour = defaultHour
    for (const blocks of dayBlockLists || [])
        for (const block of blocks || [])
            if (!block.continuesBefore) hour = Math.min(hour, Math.floor(block.start / 60))
    return Math.max(0, hour)
}
