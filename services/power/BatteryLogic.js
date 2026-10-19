.pragma library

// Low battery warnings: which threshold to announce while discharging. Each
// threshold fires once per discharge cycle and re-arms when charging starts
// or the level climbs HYSTERESIS points above it. Unit tested.

var HYSTERESIS = 3
var LOW_LEVELS = [10, 15, 20, 25]

function lowLevel(value) {
    return LOW_LEVELS.indexOf(value) >= 0 ? value : 20
}

// Thresholds from highest to lowest; the configurable one plus 10 and 5.
function thresholds(level) {
    return [lowLevel(level), 10, 5].filter((value, index, list) => list.indexOf(value) === index)
        .sort((a, b) => b - a)
}

function kindOf(threshold) {
    return threshold <= 5 ? "critical" : threshold <= 10 ? "veryLow" : "low"
}

// input: { hasBattery, discharging, percent, enabled, level }
// state: { fired: { "<threshold>": true } }
// Returns { state, warning } where warning is null or { threshold, kind }.
function update(state, input) {
    const fired = Object.assign({}, state && state.fired ? state.fired : {})
    const percent = Number(input.percent)
    if (!input.hasBattery || !input.discharging || !isFinite(percent))
        return { state: { fired: {} }, warning: null }

    const levels = thresholds(input.level)
    for (const key of Object.keys(fired)) {
        if (levels.indexOf(Number(key)) < 0 || percent > Number(key) + HYSTERESIS) delete fired[key]
    }
    if (!input.enabled) return { state: { fired: fired }, warning: null }

    // Only the most severe newly crossed threshold is announced; the higher
    // ones count as fired too, so a start at 8% gives one warning, not two.
    const crossed = levels.filter(value => percent <= value)
    if (!crossed.length) return { state: { fired: fired }, warning: null }
    const lowest = crossed[crossed.length - 1]
    const warning = fired[lowest] ? null : { threshold: lowest, kind: kindOf(lowest) }
    for (const value of crossed) fired[value] = true
    return { state: { fired: fired }, warning: warning }
}

// Notification text for a warning; `remaining` is e.g. "25 min left" or "".
function message(kind, percent, remaining) {
    const level = Math.round(Number(percent) || 0) + "%"
    const detail = remaining && remaining.length ? level + " · " + remaining : level + " remaining"
    if (kind === "critical")
        return { title: "Battery critically low", body: detail + ". Plug in the charger now to avoid losing your work.",
                 urgency: "critical", icon: "battery-empty" }
    if (kind === "veryLow")
        return { title: "Battery very low", body: detail + ". Plug in the charger soon.",
                 urgency: "critical", icon: "battery-caution" }
    return { title: "Battery low", body: detail + ".", urgency: "normal", icon: "battery-low" }
}

var TITLES = ["Battery low", "Battery very low", "Battery critically low"]

// The battery's state in words (PowerService.stateLabel).
// state: { hasBattery, full, charging, onBattery, pendingCharge, percent,
//          limit }
// `charging` is UPower's Charging alone. PendingCharge on the charger is a
// battery held at its charge threshold, which BAT0 itself reports as "Not
// charging" - and so does Plasma. With the limit known (`limit`, from
// ChargeLimitLogic.state) it says which threshold holds it: at the top the
// limit is reached, a little below it the battery waits for the lower one.
// `brief` for a tile's header, where the battery's name and its percentage
// stand beside it: "Held at 80%" for "Charge limit 80% reached", which was
// cut to "Charge limit 80% r…" there.
function stateLabel(state, brief) {
    const s = state || {}
    if (!s.hasBattery) return "AC power"
    if (s.full) return "Fully charged"
    if (s.charging) return "Charging"
    if (s.onBattery) return "On battery"
    if (!s.pendingCharge) return "Plugged in"
    const limit = s.limit || {}
    const held = limitHold(s)
    if (held === "reached") return brief === true ? "Held at " + limit.end + "%" : "Charge limit " + limit.end + "% reached"
    if (held === "waiting") return (brief === true ? "Charges below " : "Charges again below ") + limit.start + "%"
    return "Not charging"
}

// Which threshold holds a battery that waits on the charger: "reached" at
// the limit, "waiting" between the two thresholds, "" for neither. A
// percentage or so under the limit is the limit: the reading is rounded and
// settles a little below the threshold it stopped at. The battery popup
// leaves its own "Charge limit" line out while the state says it.
function limitHold(state) {
    const s = state || {}
    if (!s.hasBattery || s.full || s.charging || s.onBattery || !s.pendingCharge) return ""
    const limit = s.limit || {}
    const percent = Number(s.percent)
    if (limit.active !== true || !isFinite(percent)) return ""
    if (percent >= limit.end - 1) return "reached"
    if (limit.start > 0 && limit.start < limit.end && percent >= limit.start) return "waiting"
    return ""
}
