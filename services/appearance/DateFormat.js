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
//   "long"    Monday, October 19
//   "short"   Mon, Oct 19
//   "day"     October 19 (no weekday)
//   "year"    Monday, October 19, 2026 (the locale's long date as it is)
//   "numeric" 10/19, 19/10 or 19.10. (a cell with no room for a month's name)
//
// Settings > Desktop extras > "Date order" can put the day first or the
// month first whatever the language says (SettingsService.dateOrder): a
// German reader on an English desktop wants "19 October" and English words.
// The locale's own pattern serves wherever its order is the one asked for -
// de_DE keeps "19." and its full stop -, and the other order is one of the
// two English patterns, in the locale's words. "Short dates in numbers"
// (SettingsService.shortDateNumbers) writes the short form as the weekday and
// the numeric date, "Mon 19.10.".

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

// The orders Settings offers ("locale" is the language's own).
var ORDERS = ["locale", "dayMonth", "monthDay"]

// Whether the day comes first: as `order` says, or as the locale's long date
// does for "locale" and for anything this file does not know.
function wantsDayFirst(order, longFormat) {
    if (order === "dayMonth") return true
    if (order === "monthDay") return false
    return dayFirst(longFormat)
}

// The numbers alone, without the year: the locale's short date where its
// order is the one asked for (en_GB 19/10, en_US 10/19, de_DE 19.10.), else
// the German or the American way. One digit where one is enough - a cell
// reads "9.10.", not "09.10." - and the full stop German writes after the
// month, which went with the year.
function numericPattern(shortFormat, first) {
    const short = String(shortFormat || "")
    if (short.length && dayFirst(short) === first) {
        const list = withoutYear(runs(short))
        if (usable(list)) {
            const text = joined(list.map(run => run.letter === "d" || run.letter === "M"
                                                ? { text: run.letter, letter: run.letter } : run))
            return text === "d.M" ? "d.M." : text
        }
    }
    return first ? "d.M." : "M/d"
}

// The pattern for `form`, from the locale's long date pattern. `order` and
// `numbers` as Settings has them (left out: the locale's order, words);
// `shortFormat` is the locale's short date, which only "numeric" and the
// numbered short form read.
function pattern(longFormat, form, order, shortFormat, numbers) {
    const full = String(longFormat || "")
    const first = wantsDayFirst(order, full)
    // The locale's own pattern, where its order is the one asked for.
    const own = dayFirst(full) === first
    if (form === "numeric") return numericPattern(shortFormat, first)
    if (form === "short" && numbers === true) return "ddd " + numericPattern(shortFormat, first)
    if (form === "year" && !own) return first ? "dddd, d MMMM yyyy" : "dddd, MMMM d, yyyy"
    if (form === "year" && full.length) return full
    let list = own ? withoutYear(runs(full)) : null
    if (!usable(list)) list = runs(first ? "dddd, d MMMM" : "dddd, MMMM d")
    if (form === "day") {
        const bare = withoutWeekday(list)
        list = usable(bare) ? bare : runs(first ? "d MMMM" : "MMMM d")
    }
    if (form === "short")
        list = list.map(run => isWeekday(run) ? { text: "ddd", letter: "d" }
                         : run.letter === "M" && run.text.length > 3 ? { text: "MMM", letter: "M" } : run)
    return joined(list)
}

// The date in the locale's words and in the order asked for. `form` as
// above, "long" when left out; `order` and `numbers` from
// SettingsService.dateOrder and shortDateNumbers - left out, the locale's
// order in words, as before there was a choice.
function date(value, locale, form, order, numbers) {
    if (!value || !locale) return ""
    const kind = form || "long"
    // Locale.ShortFormat is 1: the enum is out of reach here (see above).
    const short = kind === "numeric" || (kind === "short" && numbers === true) ? locale.dateFormat(1) : ""
    return locale.toString(value, pattern(locale.dateFormat(), kind, order, short, numbers))
}
