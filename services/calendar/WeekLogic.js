.pragma library

// Dates for a week, and the synthetic events `calendar preview` shows. The
// week and day views these once laid out are gone (4f28290); only what the
// preview data needs is left.

function addDays(date, days) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

// First day of the week containing `date`; firstDay 0 = Sunday, 1 = Monday.
function weekStart(date, firstDay) {
    const first = firstDay === undefined ? 1 : firstDay
    return addDays(date, -((date.getDay() - first + 7) % 7))
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
