.pragma library
.import "EventDraftLogic.js" as Draft

// What the event editor offers for "Repeat", and how a rule reads in words.
//
// The rule grammar itself is not here: the editor sends repeat, weekday, count
// and until to scripts/calendar-helper.py, which builds the RRULE with
// scripts/lib/ical.py. One place writes rules, one place reads them - a rule
// the shell did not write is described, never rewritten.

const weekdays = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
const weekdayNames = { MO: "Monday", TU: "Tuesday", WE: "Wednesday", TH: "Thursday",
                       FR: "Friday", SA: "Saturday", SU: "Sunday" }

// Values match ical.py's FREQUENCIES plus "weekdays" and "" for no repeat.
function repeatOptions() {
    return [
        { value: "", label: "Never" },
        { value: "daily", label: "Every day" },
        { value: "weekdays", label: "Every weekday" },
        { value: "weekly", label: "Every week" },
        { value: "monthly", label: "Every month" },
        { value: "yearly", label: "Every year" }
    ]
}

function endingOptions() {
    return [
        { value: "never", label: "Never ends" },
        { value: "until", label: "Ends on a date" },
        { value: "count", label: "Ends after a number of times" }
    ]
}

// The weekday a weekly rule follows, taken from the event's own start date.
function weekdayOf(date) {
    return date instanceof Date && !isNaN(date) ? weekdays[date.getDay()] : ""
}

function repeatLabel(repeat) {
    const option = repeatOptions().find(entry => entry.value === String(repeat || ""))
    return option ? option.label : "Repeats"
}

// "Every week on Monday, 5 times". Used under the Repeat row and in the
// details of an event the shell did not create.
function describe(rule) {
    if (!rule || !rule.repeat) return "Does not repeat"
    let text = repeatLabel(rule.repeat)
    if (rule.repeat === "weekly" && weekdayNames[rule.weekday])
        text += " on " + weekdayNames[rule.weekday]
    if (rule.count > 0) text += ", " + rule.count + (rule.count === 1 ? " time" : " times")
    else if (rule.until) text += ", until " + untilDay(rule.until)
    return text
}

// An UNTIL value ("20261130T235959Z" or "20261130") as YYYY-MM-DD.
function untilDay(value) {
    const match = /^(\d{4})(\d{2})(\d{2})/.exec(String(value || ""))
    return match ? match[1] + "-" + match[2] + "-" + match[3] : ""
}

// The editor's fields for an event the helper resolved.
function ruleDraft(identity, startDate) {
    const known = !identity || identity.ruleKnown !== false
    return {
        repeat: known ? String(identity && identity.repeat || "") : "",
        weekday: String(identity && identity.weekday || "") || weekdayOf(startDate),
        ending: !identity || !identity.recurs ? "never"
            : identity.count > 0 ? "count" : identity.until ? "until" : "never",
        count: Number(identity && identity.count) > 0 ? Number(identity.count) : 10,
        until: untilDay(identity && identity.until) || "",
        known: known
    }
}

function emptyDraft(startDate) {
    return { repeat: "", weekday: weekdayOf(startDate), ending: "never", count: 10, until: "", known: true }
}

// → { ok, error }. An end date must be a date and must not be before the day
// the event starts on; a count must be a small positive number.
function validate(rule, startDay) {
    if (!rule || !rule.repeat) return { ok: true, error: "" }
    if (rule.ending === "count") {
        const count = Number(rule.count)
        if (!(count >= 1 && count <= 999 && count === Math.floor(count)))
            return { ok: false, error: "Repeat between 1 and 999 times." }
    }
    if (rule.ending === "until") {
        const until = Draft.parseDate(rule.until)
        if (!until) return { ok: false, error: "Enter the last date as YYYY-MM-DD." }
        // Both sides are parsed: compared as text, an unpadded start day
        // ("2026-9-5") sorted after every padded end date in the same year.
        const start = Draft.parseDate(startDay)
        if (start && until.getTime() < start.getTime())
            return { ok: false, error: "The repetition ends before the event starts." }
    }
    return { ok: true, error: "" }
}

// The fields the helper expects, from the editor's rule draft.
function payload(rule) {
    if (!rule || !rule.repeat) return { repeat: "", weekday: "", count: 0, until: "" }
    return {
        repeat: String(rule.repeat),
        weekday: rule.repeat === "weekly" ? String(rule.weekday || "") : "",
        count: rule.ending === "count" ? Number(rule.count) || 0 : 0,
        until: rule.ending === "until" ? String(rule.until || "") : ""
    }
}

// True when the two rule drafts would produce the same rule.
function sameRule(a, b) {
    const left = payload(a)
    const right = payload(b)
    return left.repeat === right.repeat && left.weekday === right.weekday
        && left.count === right.count && left.until === right.until
}
