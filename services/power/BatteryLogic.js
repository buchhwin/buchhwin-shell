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
