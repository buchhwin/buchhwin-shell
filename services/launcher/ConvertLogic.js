.pragma library

// Unit and currency conversions in the launcher: "10 km to mi", "3 h in min",
// "100 eur to usd", "20 C in F", "255 to hex". What counts as one, what qalc
// is asked, and what of its answer becomes the row. Unit tested
// (tests/qml/LauncherConvertTest.qml).
//
// services/launcher/Calculator.js stays the instant path for arithmetic. A
// conversion needs qalc's unit and currency tables and a process of its own
// (0.10-0.12 s and ~31 MB at its peak, gone again), so the shape is strict on
// purpose: a number, one unit, a separator and one unit. Normal app search
// never matches it, and so never starts a process.

// The words between the two sides. "in" is also the inch, which is why the
// separator is looked for from the right: in "72 in to cm" it is "to", and in
// "3 h in min" it is "in" - qalc itself reads "3 h in min" as hours times
// inches times minutes.
var SEPARATORS = { "to": true, "in": true, "into": true, "as": true, "->": true, "→": true, "=>": true }

// A number as people type it: a decimal comma is a decimal point, as in
// Calculator.js (qalc stops to ask what a comma means otherwise), and the
// typographic minus is a minus.
var NUMBER = /^[+\-−]?(?:\d+(?:[.,]\d+)?|[.,]\d+)(?:[eE][+\-]?\d+)?$/
// One unit: letters first (a currency symbol or the degree sign counts as
// one), then letters, digits and the joiners of compound units - km/h, m^2,
// m², kW·h. No spaces: "fl oz" and "nautical miles" are two words, and qalc
// read each of them as a product of prefixes and units (1E13 fL, 5036582i
// J·g·km²) - a shape that cannot be answered well is better not offered.
var UNIT = /^[A-Za-zÀ-ÖØ-öø-ÿµμΩ°$€£¥₹₽₩₺₪₫฿₴₦][A-Za-zÀ-ÖØ-öø-ÿµμΩ°$€£¥₹₽₩₺₪₫฿₴₦0-9\/^²³·*._]*$/
var SYMBOLS = "$€£¥₹₽₩₺₪₫฿₴₦"

// A bare C, F or K between two temperatures is one: qalc takes "20 C in F"
// for coulombs and farads. Only when both sides are in this table, so "1 C
// to mC" stays a charge.
var TEMPERATURE = {
    "c": "°C", "°c": "°C", "celsius": "°C", "degc": "°C",
    "f": "°F", "°f": "°F", "fahrenheit": "°F", "degf": "°F",
    "k": "K", "kelvin": "K", "kelvins": "K"
}

// Number bases and numerals, which qalc writes without a unit ("255 to hex"
// is 0xFF). They take no minus in front (see `expression`): "-hex" is an
// error there.
var BASES = { "hex": "hex", "hexadecimal": "hex", "bin": "bin", "binary": "bin",
              "oct": "oct", "octal": "oct", "roman": "roman" }

// Currencies by code (the European Central Bank's list, which qalc's rates
// come from, and bitcoin), by symbol and by name. A conversion between two of
// them depends on rates that age; the row says so while they are not fetched.
var CURRENCY_CODES = ("usd jpy bgn czk dkk gbp huf pln ron sek chf isk nok try aud brl cad cny hkd idr ils inr krw "
                      + "mxn myr nzd php sgd thb zar eur btc").split(" ")
var CURRENCY_WORDS = ("euro euros dollar dollars pound pounds yen franc francs krona kronor krone kroner "
                      + "zloty bitcoin bitcoins").split(" ")

function isCurrency(unit) {
    const text = String(unit || "").toLowerCase()
    if (!text.length) return false
    if (text.length === 1 && SYMBOLS.indexOf(text) >= 0) return true
    return CURRENCY_CODES.indexOf(text) >= 0 || CURRENCY_WORDS.indexOf(text) >= 0
}

function normalizedNumber(text) {
    return String(text).replace(/−/g, "-").replace(",", ".")
}

// The left side: "10 km" (two words), "10km" or "$100" (one word), or a bare
// number for a base. → { amount, from } or null.
function leftSide(words) {
    if (words.length === 2) {
        if (!NUMBER.test(words[0]) || !UNIT.test(words[1])) return null
        return { amount: normalizedNumber(words[0]), from: words[1] }
    }
    if (words.length !== 1) return null
    const word = words[0]
    if (NUMBER.test(word)) return { amount: normalizedNumber(word), from: "" }
    // A currency symbol in front of the number: "$100", "€12,50".
    if (SYMBOLS.indexOf(word.charAt(0)) >= 0 && NUMBER.test(word.slice(1)))
        return { amount: normalizedNumber(word.slice(1)), from: word.charAt(0) }
    // A number with its unit glued on: "10km", "100eur".
    const glued = word.match(/^([+\-−]?(?:\d+(?:[.,]\d+)?|[.,]\d+))(.+)$/)
    if (glued && UNIT.test(glued[2]) && !/^[eE]\d/.test(glued[2]))
        return { amount: normalizedNumber(glued[1]), from: glued[2] }
    return null
}

// → null, or { amount, from, to, kind: "unit" | "base", currency, expression }.
// `expression` is what qalc is given; the minus in front of the target asks
// for one unit, not qalc's mixed ones ("6 mi + 376 yd + 4.79 in").
function parse(text) {
    const words = String(text || "").trim().split(/\s+/).filter(word => word.length)
    if (words.length < 3 || words.length > 4) return null
    // The separator nearest the end that has a side on both of its sides.
    for (let index = words.length - 2; index >= 1; --index) {
        if (!SEPARATORS[words[index].toLowerCase()]) continue
        const right = words.slice(index + 1)
        if (right.length !== 1) continue
        const left = leftSide(words.slice(0, index))
        if (!left) continue
        let to = right[0]
        let from = left.from
        if (!from.length) {
            const base = BASES[to.toLowerCase()]
            if (!base) return null
            return { amount: left.amount, from: "", to: base, kind: "base", currency: false,
                     expression: left.amount + " to " + base }
        }
        if (!UNIT.test(to)) return null
        if (TEMPERATURE[from.toLowerCase()] && TEMPERATURE[to.toLowerCase()]) {
            from = TEMPERATURE[from.toLowerCase()]
            to = TEMPERATURE[to.toLowerCase()]
        }
        if (from.toLowerCase() === to.toLowerCase()) return null
        return { amount: left.amount, from: from, to: to, kind: "unit",
                 currency: isCurrency(from) && isCurrency(to),
                 expression: left.amount + " " + from + " to -" + to }
    }
    return null
}

// How long fetched exchange rates are good for: qalc's own default is a
// week, but a launcher answer is read as today's.
var RATES_AGE_MS = 24 * 60 * 60 * 1000

// And how long a fetch that failed (offline) is left before the next try.
var RATES_RETRY_MS = 10 * 60 * 1000

// Whether this run fetches the day's rates first (qalc -e, the network):
// only for a currency conversion, only when the user turned it on, and at
// most once a day.
function needsRates(parsed, enabled, fetchedAt, now) {
    return !!(parsed && parsed.currency && enabled === true
              && (!(fetchedAt > 0) || now - fetchedAt > RATES_AGE_MS))
}

// A fetch that did not happen: qalc warns about the rates (their age, or the
// download) in the same output as the answer, which it still gives from the
// rates it has.
function ratesFailed(output) {
    return /exchange rates/i.test(String(output || ""))
}

// qalc's arguments. Not terse (-t): the plain answer says how qalc read the
// input ("10 kilometers ≈ 6.213711922 mi"), which is what tells a reading
// that went wrong from one that went right. The locale is ignored so the
// answer has a decimal point whatever LC_NUMERIC says; colours off; rates
// never fetched on their own (qalc would otherwise ask on stdin); the
// calculation is cut off after two seconds.
function command(parsed, fetchRates) {
    if (!parsed) return []
    return ["qalc", "-s", "ignore locale 1", "-s", "upxrates 0", "-s", "color 0", "-m", "2000"]
        .concat(fetchRates ? ["-e"] : [])
        .concat([parsed.expression])
}

function plainUnit(text) {
    return String(text || "").toLowerCase().replace(/²/g, "2").replace(/³/g, "3").replace(/[\s^]/g, "")
}

// The answer's number, for Ctrl+Enter: "6.213711922 mi" → "6.213711922",
// "$113.78" → "113.78", "−40 °F" → "-40", "9.46E15 m" → "9.46E15".
function numberOf(text) {
    const match = String(text || "").replace(/−/g, "-").match(/-?\d+(?:\.\d+)?(?:E[+\-]?\d+)?/)
    return match ? match[0] : ""
}

// The answer as the row's title shows it: a long decimal rounded to six
// significant digits ("6.213711922 mi" → "6.21371 mi"), so the row reads
// at a glance. Whole numbers, exponents and short answers stay as they are;
// what is copied and the second line keep qalc's full answer.
var SHOWN_DIGITS = 6
function shownAnswer(text) {
    const value = String(text || "")
    const match = value.match(/^(\D{0,4}?)([\-−]?)(\d+)\.(\d+)(?![\dE])(.*)$/)
    if (!match) return value
    const whole = match[3], fraction = match[4]
    if (whole.length + fraction.length <= SHOWN_DIGITS) return value
    const number = Number(whole + "." + fraction)
    // Below one the digits that count start after the zeros: toPrecision,
    // unless that would write an exponent the answer did not have.
    const fixed = Number(whole) === 0 ? number.toPrecision(SHOWN_DIGITS) : number.toFixed(Math.max(0, SHOWN_DIGITS - whole.length))
    if (/e/i.test(fixed)) return value
    const rounded = fixed.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "")
    return match[1] + match[2] + rounded + match[5]
}

// An answer is a number with at most one unit after it, or a currency's
// symbol or code before it: "6.213711922 mi", "$113.78", "CHF 83.1781",
// "−40 °F", "1E13 fL". What qalc gives back for a unit it could not convert
// to is a formula ("−(−(1130973.355 / z) × …)" for "rpm to hz").
var ANSWER = /^(?:[^\d\s\-−]{1,4}\s?)?[\-−]?\d+(?:\.\d+)?(?:E[+\-−]?\d+)?(?:\s+\S+)?$/

// What of qalc's output is worth a row. → null, or { title, copy, number,
// echo, approximate }. Null for an error, for a guess qalc warns about ("Did
// you mean …"), for a unit it could only read as a product of prefixes ("foo"
// as femtobyte·byte, "mins" as minute·seconds - a lower-case word read with a
// "·" in it), for an answer that is not a number in one unit, and for one
// still in the unit it started in ("5 m to kg": no conversion).
function answer(output, parsed) {
    if (!parsed) return null
    const lines = String(output || "").split("\n").map(line => line.trim()).filter(line => line.length)
    if (!lines.length) return null
    if (lines.some(line => /^error:/i.test(line) || /did you mean/i.test(line))) return null
    const last = lines[lines.length - 1]
    let at = -1
    let separator = ""
    for (const candidate of [" = ", " ≈ "]) {
        const found = last.lastIndexOf(candidate)
        if (found > at) { at = found; separator = candidate.trim() }
    }
    if (at < 0) return null
    const echo = last.slice(0, at).trim()
    const result = last.slice(at + separator.length + 2).trim()
    if (!echo.length || !result.length) return null
    if (parsed.kind === "unit") {
        if (!ANSWER.test(result)) return null
        if (/^[a-z]+$/.test(parsed.from) && echo.indexOf("·") >= 0) return null
        const unit = result.replace(/^[^\d\-−]*[\-−]?\d+(?:\.\d+)?(?:E[+\-−]?\d+)?\s*/, "")
        if (plainUnit(unit) === plainUnit(parsed.from)) return null
    }
    const copy = result.replace(/−/g, "-")
    return { title: parsed.kind === "base" ? result : shownAnswer(result), full: result, copy: copy,
             number: parsed.kind === "base" ? copy : numberOf(copy), echo: echo, approximate: separator === "≈" }
}

// The row's second line: how qalc read it, the answer, and for currencies
// whether the rates are the day's.
function subtitle(parsed, result, ratesFetched) {
    if (!parsed || !result) return ""
    return result.echo + " " + (result.approximate ? "≈" : "=") + " " + (result.full || result.title)
        + (parsed.currency && !ratesFetched ? " · offline exchange rates" : "")
        + " · Enter copies"
}
