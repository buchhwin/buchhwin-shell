.pragma library

// v1: { configVersion: 1, monitors: { <screen>: { x, y, scale, visible?,
//        widgets: { clock-main|date-main|battery-main: { x, y, scale, visible } } } } }
// v2: { configVersion: 2, activeProfile, profiles: { <name>: { widgets: [], groups: [], screens: [] } } }
// v1 x was the widget's right edge, so migrated widgets anchor right.

var TYPES = { "clock-main": "clock", "date-main": "date", "battery-main": "battery" }

function number(value, fallback) {
    const result = Number(value)
    return isFinite(result) ? result : fallback
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

function widgetFrom(type, screen, source, defaults) {
    return {
        id: type + "-" + screen,
        type: type,
        screen: screen,
        anchorX: "right",
        x: clamp(number(source.x, defaults.x), 0, 1),
        y: clamp(number(source.y, defaults.y), 0, 1),
        scale: clamp(number(source.scale, 1), 0.7, 2),
        size: "small",
        style: "minimal",
        visible: source.visible === undefined ? defaults.visible : Boolean(source.visible),
        group: "",
        options: {}
    }
}

function migrate(v1) {
    const widgets = []
    const screens = []
    const monitors = v1 && typeof v1.monitors === "object" && v1.monitors ? v1.monitors : {}
    for (const screen of Object.keys(monitors)) {
        const monitor = monitors[screen] || {}
        const entries = typeof monitor.widgets === "object" && monitor.widgets ? monitor.widgets : {}
        screens.push(screen)
        let clockSource = entries["clock-main"]
        if (!clockSource && monitor.x !== undefined)
            clockSource = { x: monitor.x, y: monitor.y, scale: monitor.scale, visible: monitor.visible }
        widgets.push(widgetFrom("clock", screen, clockSource || {}, { x: 0.975, y: 0.025, visible: true }))
        for (const legacyId of Object.keys(entries)) {
            const type = TYPES[legacyId]
            if (!type || type === "clock") continue
            widgets.push(widgetFrom(type, screen, entries[legacyId] || {}, { x: 0.5, y: 0.08, visible: false }))
        }
    }
    return {
        configVersion: 2,
        activeProfile: "minimal",
        profiles: { minimal: { widgets: widgets, groups: [], screens: screens } }
    }
}
