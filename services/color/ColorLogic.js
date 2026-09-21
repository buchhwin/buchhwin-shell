.pragma library

// The colour picker's own pure parts: what counts as a colour, and the
// history, which is a comma-string because SettingsService cannot hold a list
// (`sanitizedNode` rebuilds every object with `Object.keys`, so an array
// becomes {"0": ...} on the next write of any setting).

// How many picks are kept. Long enough to find the one from a minute ago,
// short enough that the row does not become a wall.
var HISTORY_MAX = 12

var PATTERN = /^#[0-9a-f]{6}$/

function isColour(value) {
    return PATTERN.test(String(value || "").trim().toLowerCase())
}

function normalize(value) {
    const text = String(value || "").trim().toLowerCase()
    return isColour(text) ? text : ""
}

// Stored newest first, so the row reads left to right in the order they were
// taken.
function parseHistory(text) {
    const seen = {}
    return String(text || "").split(",")
        .map(normalize)
        .filter(colour => colour.length > 0 && !seen[colour] && (seen[colour] = true))
        .slice(0, HISTORY_MAX)
}

// A colour that is already in the list moves to the front rather than being
// added twice: picking the same blue again is not a second blue.
function addToHistory(history, colour) {
    const added = normalize(colour)
    if (!added.length) return (history || []).join(",")
    return [added].concat((history || []).filter(entry => entry !== added))
        .slice(0, HISTORY_MAX).join(",")
}

// Whether a swatch is light enough to want dark ink on it, by the same
// relative luminance rule the rest of the shell uses for contrast. A
// judgement, not a colour: which two colours those are is the theme's to say,
// and this file may not name one.
function isLight(colour) {
    const hex = normalize(colour)
    if (!hex.length) return false
    const channel = start => {
        const value = parseInt(hex.substr(start, 2), 16) / 255
        return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4)
    }
    const luminance = 0.2126 * channel(1) + 0.7152 * channel(3) + 0.0722 * channel(5)
    return luminance > 0.179
}
