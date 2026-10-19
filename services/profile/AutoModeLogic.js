.pragma library
.import "ProfileLogic.js" as Profile

// Which mode "Choose the mode automatically" (Settings > Profiles) picks.
//
// It knew two answers: Laptop without an external display, Docked with one
// (ProfileLogic.AUTOMATIC). Turned on, it put a user who lives in another
// mode - minimal, the notch, here - into Docked at every docking, so it
// stayed off. The targets are the user's now: At the desk, On the road, and
// optionally On battery - a laptop away from the desk and off the charger,
// where a lighter mode saves power. They ship as before (Docked, Laptop,
// nothing), so turning the switch on behaves as it always did.
//
// What decides "at the desk" is unchanged: DisplayLogic.suggestedMode
// ("docked" with an external display, "laptop" without, "" on a machine
// without a panel of its own, which keeps its mode).

var DEFAULTS = { desk: "docked", road: "laptop", battery: "" }
var KEYS = { desk: "desktop.autoModeDesk", road: "desktop.autoModeRoad", battery: "desktop.autoModeBattery" }
var SIDES = ["desk", "road", "battery"]

function modeList(modes) {
    const list = Profile.names(modes)
    return list.length ? list : Profile.MODE_NAMES.slice()
}

// One stored target: a mode of `modes`, or the side's default - a mode
// renamed or a value from a newer shell must not leave the switching with no
// target at all. Battery's default is "" (as on the road), and "" is a
// choice there.
function target(value, side, modes) {
    const fallback = Object.prototype.hasOwnProperty.call(DEFAULTS, side) ? DEFAULTS[side] : ""
    const text = typeof value === "string" ? value : ""
    if (side === "battery" && text === "") return ""
    return modeList(modes).indexOf(text) >= 0 ? text : fallback
}

// The three targets from the settings: `read` is a path -> value function
// (SettingsService.value), `modes` the profile's mode names.
function targets(read, modes) {
    const get = typeof read === "function" ? read : () => undefined
    const result = {}
    for (const side of SIDES) result[side] = target(get(KEYS[side]), side, modes)
    return result
}

// The mode to be in: `situation` is DisplayLogic.suggestedMode's answer. The
// battery target only away from the desk - at the desk the displays say where
// one is, plugged in or not - and only when one is chosen. "" for a machine
// that keeps its mode.
function suggested(situation, onBattery, chosen) {
    const t = chosen || DEFAULTS
    if (situation === "docked") return String(t.desk || DEFAULTS.desk)
    if (situation !== "laptop") return ""
    if (onBattery === true && typeof t.battery === "string" && t.battery.length) return t.battery
    return String(t.road || DEFAULTS.road)
}

// The modes the switching itself picks, for the mode key's rule
// (ProfileLogic.cycleMode): landing on one of them by hand turns the
// automatic switching on again, cycling away from them turns it off.
function owned(chosen) {
    const t = chosen || DEFAULTS
    const list = []
    for (const side of SIDES) {
        const mode = typeof t[side] === "string" ? t[side] : ""
        if (mode.length && list.indexOf(mode) < 0) list.push(mode)
    }
    return list
}

// Whether the battery target needs the power state read at all: without one
// the switching never asks (AdaptiveService reads PowerService only then).
function watchesBattery(chosen) {
    return !!chosen && typeof chosen.battery === "string" && chosen.battery.length > 0
}

// The choices for Settings: the profile's modes with their labels; battery
// leads with "As on the road" ("").
function options(side, modes, templates) {
    const list = modeList(modes).map(name => ({ value: name, label: Profile.label(name, templates) }))
    return side === "battery" ? [{ value: "", label: "As on the road" }].concat(list) : list
}
