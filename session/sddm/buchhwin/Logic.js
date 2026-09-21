.pragma library

// Pure helpers of the SDDM theme (tested in tests/qml/SddmThemeTest.qml).
// SDDM cannot load the shell's qs.* modules, so nothing here imports them.

// theme.conf values arrive as strings; QSettings turns values with commas
// into lists.
function configString(value, fallback) {
    if (value === undefined || value === null) return fallback
    const text = Array.isArray(value) ? value.join(", ") : String(value)
    return text.trim().length ? text.trim() : fallback
}

// What the login screen can honour of the lock screen's arrangement.
//
// `lockItems` arrives as a comma-string from install/sddm-theme.sh. The theme
// is a separate QML application: it cannot import the shell's components, so
// it has the blocks it has - the clock, the date and the keyboard layout - and
// no grid at all. Anything else in the list is simply not something this
// screen can draw, and saying so here is more honest than pretending.
var LOGIN_BLOCKS = ["clock", "date", "keyboard"]

function lockItems(value) {
    const text = configString(value, "")
    if (!text.length) return LOGIN_BLOCKS
    const wanted = text.split(",").map(part => part.trim()).filter(part => part.length)
    const known = wanted.filter(part => LOGIN_BLOCKS.indexOf(part) >= 0)
    // An arrangement that names none of them is not an instruction to show an
    // empty login screen; it is an arrangement about things this screen does
    // not have, and the clock stays.
    return known.length ? known : ["clock"]
}

function showsBlock(items, name) {
    return (items || []).indexOf(name) >= 0
}

// Whether the date sits above the clock or below it, which is the one piece of
// order the theme can act on.
function dateAboveClock(items) {
    const list = items || []
    const date = list.indexOf("date")
    const clock = list.indexOf("clock")
    return date >= 0 && clock >= 0 ? date < clock : true
}

function configBool(value, fallback) {
    if (typeof value === "boolean") return value
    const text = configString(value, "").toLowerCase()
    if (["true", "yes", "on", "1"].indexOf(text) >= 0) return true
    if (["false", "no", "off", "0"].indexOf(text) >= 0) return false
    return fallback
}

function configColor(value, fallback) {
    const text = configString(value, "")
    return /^#[0-9a-fA-F]{6}$/.test(text) ? text : fallback
}

// Relative paths resolve next to Main.qml (the installed theme directory).
function imageUrl(path) {
    const text = configString(path, "")
    if (!text.length) return ""
    if (/^[a-z]+:\/\//.test(text)) return text
    return text.charAt(0) === "/" ? "file://" + text : text
}

// A valid row of a model, or the first one.
function clampIndex(index, count) {
    const value = Number(index)
    if (!(count > 0)) return -1
    return Number.isInteger(value) && value >= 0 && value < count ? value : 0
}

function nextIndex(index, count) {
    return count > 0 ? (clampIndex(index, count) + 1) % count : -1
}

function displayName(realName, name) {
    return configString(realName, configString(name, ""))
}

// First letter or digit, upper-case.
function initial(name) {
    const first = Array.from(configString(name, "")).find(c => /[0-9]/.test(c) || c.toLocaleUpperCase() !== c.toLocaleLowerCase())
    return first ? first.toLocaleUpperCase() : "?"
}

// SDDM reports FacesDir/.face.icon when a user has no picture of their own;
// that generic face is replaced by the initial.
function hasOwnFace(icon) {
    const text = configString(icon, "")
    return text.length > 0 && !/\/sddm\/faces\/\.face\.icon$/.test(text)
}

function sessionLabel(name, file) {
    return configString(name, configString(file, "").replace(/\.desktop$/, "")) || "Session"
}

// Staggered entrance like the lock screen: `step` of `steps` starts
// stagger/enter later; leaving (reverse) moves everything at once.
function stagger(fade, step, steps, staggerMs, enterMs, reverse) {
    if (!(enterMs > 0)) return Math.max(0, Math.min(1, fade))
    const span = steps * staggerMs / enterMs
    const offset = reverse ? 0 : step * staggerMs / enterMs
    return Math.max(0, Math.min(1, fade * (1 + span) - offset))
}

// Keyboard layout short name for the indicator ("de", "us" → "DE", "US").
function layoutLabel(layouts, current) {
    if (!layouts || !(layouts.length > 0)) return ""
    const layout = layouts[clampIndex(current, layouts.length)]
    return layout ? configString(layout.shortName, configString(layout.longName, "")).toUpperCase() : ""
}

// SDDM only reports Caps Lock through X11; the Wayland greeter guesses it
// from typed letters: an upper-case letter without Shift (or a lower-case one
// with Shift) means it is on. The Caps Lock key flips a known state.
function capsGuess(previous, text, shift, capsKey) {
    if (capsKey) return previous === null ? null : !previous
    if (typeof text !== "string" || Array.from(text).length !== 1) return previous
    const upper = text.toLocaleUpperCase()
    const lower = text.toLocaleLowerCase()
    if (upper === lower) return previous
    return (text === upper) !== shift
}

// Text below the password field: a message from the daemon wins, then Caps Lock.
function statusText(status, capsLock) {
    if (configString(status, "").length) return status
    return capsLock ? "Caps Lock is on" : ""
}
