.pragma library

// Separate power settings for "On battery" and "Plugged in" (Settings >
// Power): which set applies, the one-time migration from the single values
// used before the split and the power profile to apply when the source
// changes. Unit tested.

var SOURCES = ["battery", "ac"]
// Settings that exist once per source (power.battery.KEY, power.ac.KEY).
var KEYS = ["screenOffMinutes", "lockMinutes", "suspendMinutes", "dimBeforeScreenOff", "lidAction", "profile"]
// Single power.KEY values before the split; they seed both sources.
var LEGACY_KEYS = ["screenOffMinutes", "lockMinutes", "suspendMinutes", "dimBeforeScreenOff", "lidAction"]
var PROFILES = ["keep", "powerSaver", "balanced", "performance"]

// Battery settings apply only while a laptop battery powers the machine;
// desktops and plugged-in laptops use the "ac" set.
function source(hasBattery, onBattery) {
    return hasBattery && onBattery ? "battery" : "ac"
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

// document: parsed settings.json. Returns the document unchanged when it
// already has per-source settings, otherwise a copy where both sources start
// with the old single values and the profile stays unchanged ("keep"), so an
// update changes nothing the user did not choose.
function migrate(document) {
    if (!isObject(document)) return document
    const power = isObject(document.power) ? document.power : {}
    if (isObject(power.battery) || isObject(power.ac)) return document
    const result = Object.assign({}, document)
    const next = {}
    for (const key of Object.keys(power)) {
        if (LEGACY_KEYS.indexOf(key) < 0) next[key] = power[key]
    }
    for (const name of SOURCES) {
        const values = { profile: "keep" }
        for (const key of LEGACY_KEYS) {
            if (power[key] !== undefined && power[key] !== null) values[key] = power[key]
        }
        next[name] = values
    }
    result.power = next
    return result
}

// Profile to apply: when the power source changes, and when the *choice* for
// the current source changes. The second half was missing, and it is the half a
// user meets: picking "Performance" for the charger while already on the
// charger did nothing at all until the next unplug and plug. An option that
// does not do what it says.
//
// The first source seen after the shell starts is still only remembered, so a
// reload keeps a manual choice - at that moment nothing has changed yet, and
// the shell has no business overruling a profile the user set by hand.
//
// state: { source, choice } (source "" before UPower is ready)
// input: { ready, source, choice } where choice is one of PROFILES
// Returns { state, profile } with profile "" when nothing should change.
function profileChange(state, input) {
    const last = state && typeof state.source === "string" ? state.source : ""
    const lastChoice = state && typeof state.choice === "string" ? state.choice : ""
    if (!input || !input.ready || SOURCES.indexOf(input.source) < 0)
        return { state: { source: last, choice: lastChoice }, profile: "" }
    const next = { source: input.source, choice: typeof input.choice === "string" ? input.choice : "" }
    // "keep" is index 0 and means "do not touch the profile at all".
    const choice = PROFILES.indexOf(input.choice) > 0 ? input.choice : ""
    if (!last.length) return { state: next, profile: "" }
    if (last !== next.source || lastChoice !== next.choice) return { state: next, profile: choice }
    return { state: next, profile: "" }
}
