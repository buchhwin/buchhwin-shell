.pragma library

// Pure helpers for keyboard, mouse and touchpad settings, applied as Hyprland
// `input:*` options through HyprCompat. Unit tested.

// Layouts and variants from an xkb rules list (/usr/share/X11/xkb/rules/evdev.lst).
function parseXkbList(text) {
    const layouts = []
    const variants = {}
    let section = ""
    for (const line of String(text || "").split("\n")) {
        const header = /^!\s*(\w+)/.exec(line)
        if (header) { section = header[1]; continue }
        if (section === "layout") {
            const match = /^\s+(\S+)\s+(.+)$/.exec(line)
            if (match) layouts.push({ value: match[1], label: match[2].trim() })
        } else if (section === "variant") {
            const match = /^\s+(\S+)\s+(\S+):\s+(.+)$/.exec(line)
            if (match) {
                if (!variants[match[2]]) variants[match[2]] = []
                variants[match[2]].push({ value: match[1], label: match[3].trim() })
            }
        }
    }
    layouts.sort((a, b) => a.label.localeCompare(b.label))
    return { layouts: layouts, variants: variants }
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
}

// Touchpad scroll speed: 0.2-2, anything unusable keeps libinput's own steps.
function scrollFactor(value) {
    const number = Number(value)
    if (!isFinite(number)) return 1
    return Math.round(clamp(number, 0.2, 2) * 100) / 100
}

// Sanitised values for the given settings getter (path -> value).
function values(get) {
    const layout = /^[a-z0-9_,-]+$/i.test(get("input.kbLayout")) ? get("input.kbLayout") : "de"
    const variant = /^[a-z0-9_,-]*$/i.test(get("input.kbVariant")) ? get("input.kbVariant") : ""
    return {
        kb_layout: layout,
        kb_variant: variant,
        repeat_rate: Math.round(clamp(get("input.repeatRate"), 10, 80)),
        repeat_delay: Math.round(clamp(get("input.repeatDelay"), 150, 1000)),
        sensitivity: Math.round(clamp(get("input.sensitivity"), -1, 1) * 100) / 100,
        accel_profile: get("input.accelProfile") === "flat" ? "flat" : "adaptive",
        natural_scroll: get("input.mouseNaturalScroll") === true,
        "touchpad:natural_scroll": get("input.touchpadNaturalScroll") !== false,
        // Touchpad scroll speed; 1 keeps libinput's own steps.
        "touchpad:scroll_factor": scrollFactor(get("input.touchpadScrollFactor")),
        "touchpad:tap-to-click": get("input.tapToClick") !== false,
        "touchpad:disable_while_typing": get("input.disableWhileTyping") !== false
    }
}

// Hyprland option map: { "input:kb_layout": "de", ... }.
function optionMap(settings) {
    const result = {}
    for (const key of Object.keys(settings)) result["input:" + key] = settings[key]
    return result
}
