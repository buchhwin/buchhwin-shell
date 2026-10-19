.pragma library

// Stay awake (IdleService): screen off, lock and sleep paused, for an hour,
// until the charger is unplugged or until it is turned off. It used to be a
// plain switch with no end and no mark anywhere: left on, it was no lock and
// no sleep - a battery run down on the train, a laptop left unlocked on the
// desk. A hold that ends by itself is the one a quick switch starts unless
// the user picked another. Unit tested (StayAwakeTest).

var MODES = ["off", "1h", "unplug", "manual"]
// The ways a hold can end; a quick switch starts the one chosen last.
var LIMITS = ["1h", "unplug", "manual"]
var HOUR = 3600000
var MINUTE = 60000

function normalLimit(value) {
    return LIMITS.indexOf(value) >= 0 ? value : "1h"
}

// Whether a mode can be started now. "Until the charger is unplugged" needs a
// battery and a charger to unplug: on a desktop or on battery it would end at
// once, or never.
// ctx: { hasBattery, onBattery }
function offered(mode, ctx) {
    if (MODES.indexOf(mode) < 0) return false
    if (mode !== "unplug") return true
    const c = ctx || {}
    return c.hasBattery === true && c.onBattery !== true
}

// The hold a mode starts: { mode, until } (until in ms since the epoch, 0
// unless timed), or null for a mode that cannot be started now.
// ctx: { now, hasBattery, onBattery }
function start(mode, ctx) {
    if (!offered(mode, ctx)) return null
    const now = Number((ctx || {}).now)
    if (mode === "1h") return isFinite(now) ? { mode: mode, until: now + HOUR } : null
    return { mode: mode, until: 0 }
}

// What a quick switch starts: the limit chosen last, or an hour where that
// one is not offered (the charger was the last choice, and now there is none).
function quickMode(limit, ctx) {
    const wanted = normalLimit(limit)
    return offered(wanted, ctx) ? wanted : "1h"
}

// Whether a running hold is over. A timed one ends at its deadline, by the
// wall clock: Qt's timers stand still in a suspend, and an hour started
// before a night in the bag is long over in the morning.
// state: { mode, until }; ctx: { now, hasBattery, onBattery }
function ended(state, ctx) {
    const s = state || {}
    const c = ctx || {}
    if (s.mode === "1h") return !(Number(c.now) < Number(s.until))
    if (s.mode === "unplug") return c.hasBattery === true && c.onBattery === true
    return false
}

// How long the timer waits before it looks again: to the next whole minute
// of what is left, so "12 min left" turns to 11 when it is true, and never
// past the deadline. A timer can fire a little early (Date.now() is not its
// clock); it then finds the hold still running and waits for the rest.
function nextCheck(until, now) {
    const left = Number(until) - Number(now)
    if (!isFinite(left)) return MINUTE
    if (left <= 0) return 0
    const toMinute = left % MINUTE
    return Math.max(1, Math.min(left, toMinute > 0 ? toMinute : MINUTE))
}

// Whole minutes left, rounded up: a hold with 30 s to go says "1 min".
function minutesLeft(until, now) {
    const left = Number(until) - Number(now)
    return isFinite(left) && left > 0 ? Math.ceil(left / MINUTE) : 0
}

// The second line under a switch, a tile or a row.
function subtitle(mode, until, now) {
    if (mode === "1h") {
        const minutes = minutesLeft(until, now)
        return minutes >= 60 ? "1 h left" : minutes + " min left"
    }
    if (mode === "unplug") return "Until unplugged"
    if (mode === "manual") return "Until turned off"
    return "Off"
}

// The choices in their order, in the same words wherever they are offered:
// the control center's list and Settings > Power's row.
function title(mode) {
    return mode === "1h" ? "For 1 hour"
        : mode === "unplug" ? "Until unplugged"
        : mode === "manual" ? "Until turned off"
        : "Off"
}
