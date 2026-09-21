.pragma library

// Keyboard backlight: which step it is on, what that step is called, and where
// the next one is.
//
// It is a stepped light, not a dimmer. This ThinkPad has `max_brightness` 2,
// so three levels; other machines have one step or four. A percentage would
// read "0% / 50% / 100%" on a track that looks like a hundred, which promises
// a fineness the hardware does not have - so the OSD says the step's name and
// draws one box per step. Nothing here hard-codes three: `maximum` decides.

// The name of a level. Words while there are few enough for words to mean
// something; past that, numbering, because nothing but the hardware knows what
// a fifth step is called.
var WORDS = {
    1: ["Off", "On"],
    2: ["Off", "Low", "High"],
    3: ["Off", "Low", "Medium", "High"]
}

function steps(maximum) {
    const max = Math.floor(Number(maximum))
    return isFinite(max) && max > 0 ? max : 0
}

function clamp(current, maximum) {
    const max = steps(maximum)
    const level = Math.round(Number(current))
    if (!isFinite(level)) return 0
    return Math.max(0, Math.min(max, level))
}

function label(current, maximum) {
    const max = steps(maximum)
    if (max <= 0) return ""
    const level = clamp(current, max)
    const words = WORDS[max]
    if (words) return words[level]
    return level === 0 ? "Off" : Math.round(level / max * 100) + "%"
}

// How many boxes the OSD cuts its track into. Past six they stop being
// countable at a glance and a plain track is the honest drawing again; 0 means
// "draw it continuous".
function segments(maximum) {
    const max = steps(maximum)
    return max > 0 && max <= 6 ? max : 0
}

// One step, clamped at both ends. It does not wrap: a key held down should
// stop at the brightest rather than start again at off.
function step(current, maximum, delta) {
    const move = Math.round(Number(delta))
    return clamp(clamp(current, maximum) + (isFinite(move) ? move : 0), maximum)
}

// Off from anywhere, and back to the brightest from off. The step the light
// was on before is not remembered on purpose: the toggle key is pressed to see
// the keyboard, and half-lit is not what that asks for.
function toggle(current, maximum) {
    return clamp(current, maximum) > 0 ? 0 : steps(maximum)
}

function fraction(current, maximum) {
    const max = steps(maximum)
    return max > 0 ? clamp(current, max) / max : 0
}

// A sysfs brightness file holds one whole number and nothing else. Anything
// else is *no answer*, which is not the same as zero - a keyboard whose light
// is off must not read as a keyboard that has no light at all, or the OSD and
// the control it belongs to would appear on every machine.
function parseLevel(text) {
    const value = String(text === undefined || text === null ? "" : text).trim()
    return /^\d+$/.test(value) ? parseInt(value, 10) : null
}

// The first keyboard-backlight LED in `ls -1 /sys/class/leds`. The prefix is
// the driver's: tpacpi on a ThinkPad, asus, dell, smc elsewhere - so the name
// is matched on its tail and never spelled out.
function deviceFrom(listing) {
    const lines = String(listing || "").split("\n")
    for (const line of lines) {
        const name = line.trim()
        if (name.length && /kbd_backlight$/.test(name)) return name
    }
    return ""
}
