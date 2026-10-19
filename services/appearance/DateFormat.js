.pragma library

// The one place a date is turned into words, as TimeFormat.js is for a time.
//
// The order of day and month is the locale's: "Monday, October 19" in en_US,
// "Monday, 19 October" in en_GB, "Montag, 19. Oktober" in de_DE. The shell
// used to write fixed patterns - "dddd, MMMM d" on the dashboard, in the
// popups, the event editor and the widgets, "dddd, d MMMM" on the lock screen
// and the notch - so under one locale the same day read both ways. Qt has no
// pattern for a date without its year, so it is the locale's own long date
// (`dateFormat()`) with the year taken off; where the year does not come off
// cleanly, the order of the locale's day and month picks one of the two
// English patterns.
//
// `locale` is a QML locale (SettingsService.locale). Its long pattern is
// `dateFormat()` without an argument, so nothing here needs the QML `Locale`
// enum, which a pragma library cannot reach.
//
// The forms:
//   "long"  Monday, October 19
//   "short" Mon, Oct 19
//   "day"   October 19 (no weekday)
//   "year"  Monday, October 19, 2026 (the locale's long date as it is)

// A pattern as runs of one pattern letter ({ text, letter }: "dddd" is
// { "dddd", "d" }) and of literal text between them (letter ""), quoted
// literals ('de', 'г') included as they are.
function runs(format) {
    const text = String(format || "")
    const out = []
    let index = 0
    while (index < text.length) {
        const first = text.charAt(index)
        let end = index + 1
        if (first === "'") {
            const close = text.indexOf("'", index + 1)
            end = close < 0 ? text.length : close + 1
            out.push({ text: text.slice(index, end), letter: "" })
        } else if (/[A-Za-z]/.test(first)) {
            while (end < text.length && text.charAt(end) === first) end += 1
            out.push({ text: text.slice(index, end), letter: first })
        } else {
            while (end < text.length && text.charAt(end) !== "'" && !/[A-Za-z]/.test(text.charAt(end))) end += 1
            out.push({ text: text.slice(index, end), letter: "" })
        }
        index = end
    }
    return out
}

function joined(list) {
    return list.map(run => run.text).join("").trim()
}

function isDay(run) { return run.letter === "d" && run.text.length <= 2 }
function isWeekday(run) { return run.letter === "d" && run.text.length >= 3 }

// The year and what belongs to it: the separator before it (", " in en_US,
// " 'de' " in Spanish) when it ends the pattern, its marker after it ("年",
// ". ", " 'm'. ") when it starts it. A year anywhere else is not taken off.
function withoutYear(list) {
    const letters = list.map((run, index) => run.letter.length ? index : -1).filter(index => index >= 0)
    const year = list.findIndex(run => run.letter === "y")
    if (year < 0) return list
    if (year === letters[letters.length - 1])
        return list.slice(0, letters.length > 1 ? letters[letters.length - 2] + 1 : 0)
    if (year === letters[0]) return list.slice(letters.length > 1 ? letters[1] : list.length)
    return null
}

// The weekday and the commas and spaces between it and the date; any other
// literal next to it is the date's ("日" in Japanese, "." after a day).
function withoutWeekday(list) {
    const at = list.findIndex(isWeekday)
    if (at < 0) return list
    const out = list.slice()
    out.splice(at, 1)
    const trim = (index, pattern) => {
        if (index < 0 || index >= out.length || out[index].letter.length) return
        const text = out[index].text
        if (text.charAt(0) === "'") return
        out[index] = { text: text.replace(pattern, ""), letter: "" }
    }
    trim(at - 1, /[\s,]+$/)
    trim(at, /^[\s,]+/)
    return out
}

// Whether a pattern is one this file can stand behind: a day of the month, a
// month, and no year left in it.
function usable(list) {
    return list !== null && list.some(isDay) && list.some(run => run.letter === "M")
        && !list.some(run => run.letter === "y")
}

// Day before month in the locale's pattern (en_GB, de_DE), or month first
// (en_US).
function dayFirst(format) {
    const list = runs(format)
    const day = list.findIndex(isDay)
    const month = list.findIndex(run => run.letter === "M")
    return day >= 0 && month >= 0 && day < month
}

// The pattern for `form`, from the locale's long date pattern.
function pattern(longFormat, form) {
    const full = String(longFormat || "")
    if (form === "year" && full.length) return full
    let list = withoutYear(runs(full))
    if (!usable(list)) list = runs(dayFirst(full) ? "dddd, d MMMM" : "dddd, MMMM d")
    if (form === "day") {
        const bare = withoutWeekday(list)
        list = usable(bare) ? bare : runs(dayFirst(full) ? "d MMMM" : "MMMM d")
    }
    if (form === "short")
        list = list.map(run => isWeekday(run) ? { text: "ddd", letter: "d" }
                         : run.letter === "M" && run.text.length > 3 ? { text: "MMM", letter: "M" } : run)
    return joined(list)
}

// The date as words in the locale's order. `form` as above; "long" when
// left out.
function date(value, locale, form) {
    if (!value || !locale) return ""
    return locale.toString(value, pattern(locale.dateFormat(), form || "long"))
}
