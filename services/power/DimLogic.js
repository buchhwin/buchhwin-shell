.pragma library

// Dim stage before the screen turns off: the backlight drops to a fraction of
// its value LEAD_SECONDS before screen off and the saved raw value comes back
// on activity, when the screen turns on again or when dimming is no longer
// allowed. Unit tested.

var LEAD_SECONDS = 30
var FACTOR = 0.3

// Idle seconds before dimming; 0 means no dim stage.
function dimTimeout(screenOffMinutes) {
    const minutes = Number(screenOffMinutes) || 0
    return minutes > 0 ? Math.max(1, minutes * 60 - LEAD_SECONDS) : 0
}

// Raw dimmed value, never 0 (some panels switch the backlight off at 0).
function dimTarget(current, maximum) {
    if (!(maximum > 0) || !(current > 0)) return current
    return Math.max(1, Math.min(current, Math.round(current * FACTOR)))
}

// state: { dimmed, saved }; event: idle | active | screenOn | disabled
// context: { allowed, current, maximum, screenOff }
// Returns { state, write } where write is the raw value to set or -1.
function next(state, event, context) {
    const dimmed = !!(state && state.dimmed)
    const saved = state && state.saved > 0 ? state.saved : 0
    if (event === "idle") {
        if (dimmed || !context.allowed || context.screenOff) return { state: { dimmed: dimmed, saved: saved }, write: -1 }
        const target = dimTarget(context.current, context.maximum)
        if (!(target < context.current)) return { state: { dimmed: false, saved: 0 }, write: -1 }
        return { state: { dimmed: true, saved: context.current }, write: target }
    }
    if (event === "active" || event === "screenOn" || event === "disabled") {
        if (!dimmed) return { state: { dimmed: false, saved: 0 }, write: -1 }
        return { state: { dimmed: false, saved: 0 }, write: saved > 0 ? saved : -1 }
    }
    return { state: { dimmed: dimmed, saved: saved }, write: -1 }
}
