.pragma library

// Pure helpers for monitor configuration through Hyprland (`hyprctl -j
// monitors all` in; rules go out through HyprCompat). Unit tested.

var SCALES = [1, 1.25, 1.5, 1.75, 2]
var TRANSFORMS = [
    { value: 0, label: "Normal" },
    { value: 1, label: "90°" },
    { value: 2, label: "180°" },
    { value: 3, label: "270°" }
]
var VRR = [
    { value: 0, label: "Off" },
    { value: 1, label: "On" },
    { value: 2, label: "Fullscreen only" }
]

function round2(value) {
    return Math.round(Number(value) * 100) / 100
}

// The scales a saved file may ask for: the presets and anything in between
// or near them. Half is the smallest Hyprland accepts without complaint and
// three is beyond any panel the shell has met; a number outside that range
// is a file written by hand or by a bug, and the monitor keeps its own.
var SCALE_MIN = 0.5
var SCALE_MAX = 3

function validScale(value) {
    const scale = Number(value)
    return isFinite(scale) && scale >= SCALE_MIN && scale <= SCALE_MAX
}

// The scale Hyprland actually runs a mode at. A scale that does not divide
// the mode into whole logical pixels is corrected by the compositor
// (src/output/Monitor.cpp, applyMonitorRule): it is taken to the nearest
// 1/120, and if that still leaves a fraction, the first multiple of 1/120
// above or below that gives whole numbers wins - up before down at each
// distance, up to 89 steps. The rule still sends the two-decimal value;
// the geometry has to use what Hyprland makes of it, or every position
// computed from the shell's width is wrong by the difference. 1.67 on a 4K
// screen is 200/120 and 2304 wide, not 2299: the shell wrote x = 2299 for
// the next monitor on 2026-10-09, five pixels inside its neighbour, and its
// own overlap check, built on the same width, saw nothing.
function effectiveScale(scale, width, height) {
    const asked = Number(scale) || 1
    const w = Number(width) || 0, h = Number(height) || 0
    if (w <= 0 || h <= 0) return asked
    const whole = s => (w / s) === Math.round(w / s) && (h / s) === Math.round(h / s)
    if (whole(asked)) return asked
    const search = Math.round(asked * 120)
    if (whole(search / 120)) return search / 120
    for (let i = 1; i < 90; ++i) {
        if (whole((search + i) / 120)) return (search + i) / 120
        if (search - i > 0 && whole((search - i) / 120)) return (search - i) / 120
    }
    return asked
}

function modeKey(width, height, refresh) {
    return width + "x" + height + "@" + round2(refresh).toFixed(2)
}

function parseModeString(text) {
    const match = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(text || ""))
    return match ? { width: Number(match[1]), height: Number(match[2]), refresh: round2(match[3]) } : null
}

// Normalised monitors; the current mode is always part of `modes`.
function parseMonitors(json) {
    const list = typeof json === "string" ? JSON.parse(json) : json
    if (!Array.isArray(list)) return []
    return list.filter(item => item && typeof item.name === "string").map(item => {
        const current = { width: Number(item.width) || 0, height: Number(item.height) || 0, refresh: round2(item.refreshRate || 60) }
        const seen = {}
        const modes = (Array.isArray(item.availableModes) ? item.availableModes : [])
            .map(parseModeString).filter(Boolean).concat([current])
            .filter(mode => mode.width > 0 && !seen[modeKey(mode.width, mode.height, mode.refresh)]
                    && (seen[modeKey(mode.width, mode.height, mode.refresh)] = true))
            .sort((a, b) => b.width * b.height - a.width * a.height || b.refresh - a.refresh)
        return {
            name: item.name,
            description: String(item.description || ""),
            make: String(item.make || ""),
            model: String(item.model || ""),
            width: current.width,
            height: current.height,
            refresh: current.refresh,
            x: Number(item.x) || 0,
            y: Number(item.y) || 0,
            scale: round2(item.scale || 1),
            transform: [0, 1, 2, 3, 4, 5, 6, 7].indexOf(Number(item.transform)) >= 0 ? Number(item.transform) : 0,
            vrr: item.vrr === true ? 1 : Number(item.vrr) === 2 ? 2 : 0,
            disabled: item.disabled === true,
            focused: item.focused === true,
            modes: modes
        }
    }).sort((a, b) => a.x - b.x || a.y - b.y || a.name.localeCompare(b.name))
}

function resolutions(monitor) {
    const seen = {}
    return monitor.modes.filter(mode => !seen[mode.width + "x" + mode.height] && (seen[mode.width + "x" + mode.height] = true))
        .map(mode => ({ value: mode.width + "x" + mode.height, label: mode.width + " × " + mode.height }))
}

// Whole hertz reads best, but a screen that offers 59.94 and 60.00 at the same
// resolution would show two segments both saying "60 Hz". Only the rates
// whose whole-hertz labels collide get their two decimals back.
function refreshRates(monitor, width, height) {
    const modes = monitor.modes.filter(mode => mode.width === width && mode.height === height)
    const count = {}
    modes.forEach(mode => { count[Math.round(mode.refresh)] = (count[Math.round(mode.refresh)] || 0) + 1 })
    return modes.map(mode => ({ value: mode.refresh.toFixed(2),
        label: (count[Math.round(mode.refresh)] > 1 ? mode.refresh.toFixed(2) : String(Math.round(mode.refresh))) + " Hz" }))
}

function scaleChoices(current) {
    const list = SCALES.slice()
    if (list.indexOf(round2(current)) < 0) list.push(round2(current))
    return list.sort((a, b) => a - b)
}

// Size in layout (logical) pixels, honouring scale and rotation - at the
// scale Hyprland runs the mode at (effectiveScale), rounded the way it rounds.
function logicalSize(monitor) {
    const rotated = monitor.transform % 2 === 1
    const scale = effectiveScale(monitor.scale || 1, monitor.width, monitor.height)
    const width = (rotated ? monitor.height : monitor.width) / scale
    const height = (rotated ? monitor.width : monitor.height) / scale
    return { width: Math.round(width), height: Math.round(height) }
}

// The one scale X11 gets. X11 has a single DPI for its whole screen, so with
// Settings > Displays > "Sharp X11 applications" on, its clients are told the
// largest scale any enabled monitor runs at: that is the screen the setting
// exists for, and an X11 window carried to the smaller screen is then a
// little large rather than a third small on the big one. 1 while nothing is
// scaled, which is also "nothing to tell".
function x11Scale(monitors) {
    let best = 1
    for (const monitor of (Array.isArray(monitors) ? monitors : []))
        if (monitor && !monitor.disabled && round2(monitor.scale) > best) best = round2(monitor.scale)
    return best
}

function ruleFor(monitor) {
    if (monitor.disabled) return monitor.name + ",disable"
    return monitor.name + "," + monitor.width + "x" + monitor.height + "@" + round2(monitor.refresh).toFixed(2)
        + "," + Math.round(monitor.x) + "x" + Math.round(monitor.y) + "," + round2(monitor.scale)
        + ",transform," + monitor.transform + ",vrr," + monitor.vrr
}

function update(monitors, name, patch) {
    return monitors.map(monitor => monitor.name === name ? Object.assign({}, monitor, patch) : monitor)
}

function enabledCount(monitors) {
    return monitors.filter(monitor => !monitor.disabled).length
}

function changed(before, after) {
    return JSON.stringify(before.map(ruleFor)) !== JSON.stringify(after.map(ruleFor))
}

// Shift enabled monitors so the layout starts at 0,0.
function normalize(monitors) {
    const enabled = monitors.filter(monitor => !monitor.disabled)
    if (!enabled.length) return monitors
    const minX = Math.min.apply(null, enabled.map(monitor => monitor.x))
    const minY = Math.min.apply(null, enabled.map(monitor => monitor.y))
    return monitors.map(monitor => monitor.disabled ? monitor : Object.assign({}, monitor, { x: monitor.x - minX, y: monitor.y - minY }))
}

// Snap a dragged monitor (logical position) to the edges of the others:
// side by side horizontally or vertically, aligned at the matching edge.
function snap(monitors, name, x, y, threshold) {
    const target = monitors.find(monitor => monitor.name === name)
    if (!target) return { x: x, y: y }
    const size = logicalSize(target)
    let bestX = x, bestY = y, dx = threshold + 1, dy = threshold + 1
    for (const other of monitors) {
        if (other.name === name || other.disabled) continue
        const o = logicalSize(other)
        const xs = [other.x + o.width, other.x - size.width, other.x, other.x + o.width - size.width]
        const ys = [other.y + o.height, other.y - size.height, other.y, other.y + o.height - size.height]
        for (const candidate of xs) if (Math.abs(candidate - x) < dx) { dx = Math.abs(candidate - x); bestX = candidate }
        for (const candidate of ys) if (Math.abs(candidate - y) < dy) { dy = Math.abs(candidate - y); bestY = candidate }
    }
    return placeApart(monitors, name, dx <= threshold ? bestX : Math.round(x), dy <= threshold ? bestY : Math.round(y))
}

// A place for the monitor that overlaps nobody: from `x`,`y`, the monitor is
// moved out of every enabled monitor it would cover, each time along the
// axis that needs the smaller move and towards the side its centre is on,
// until it is clear. Dropped half onto a neighbour it pops out to that
// neighbour's edge; dropped squarely onto one it lands below or beside it,
// whichever is nearer. Hyprland keeps explicit positions exactly as given
// and only warns about an overlap, with input landing on the wrong screen,
// so no position may leave here overlapping.
function placeApart(monitors, name, x, y) {
    const target = monitors.find(monitor => monitor.name === name)
    let px = Math.round(x), py = Math.round(y)
    if (!target) return { x: px, y: py }
    const size = logicalSize(target)
    for (let pass = 0; pass < 8; ++pass) {
        let moved = false
        for (const other of monitors) {
            if (other.name === name || other.disabled) continue
            const o = logicalSize(other)
            const overlapX = Math.min(px + size.width, other.x + o.width) - Math.max(px, other.x)
            const overlapY = Math.min(py + size.height, other.y + o.height) - Math.max(py, other.y)
            if (overlapX <= 0 || overlapY <= 0) continue
            if (overlapX <= overlapY) px += px + size.width / 2 < other.x + o.width / 2 ? -overlapX : overlapX
            else py += py + size.height / 2 < other.y + o.height / 2 ? -overlapY : overlapY
            moved = true
        }
        if (!moved) break
    }
    return { x: px, y: py }
}

// The whole layout without overlaps: enabled monitors are placed one after
// another, left to right and top to bottom, each pushed out of the ones
// already placed (placeApart). A clean layout comes back unchanged. This is
// what a saved file goes through on load - positions summed from the
// shell's old, too-short widths come back five pixels apart from each other
// - and what a resolution, scale or rotation change goes through, since
// those change a monitor's size under its neighbours.
function spread(monitors) {
    const result = monitors.slice()
    const order = result.map((monitor, index) => index).filter(index => !result[index].disabled)
        .sort((a, b) => result[a].x - result[b].x || result[a].y - result[b].y)
    const placed = []
    for (const index of order) {
        const position = placeApart(placed.concat([result[index]]), result[index].name, result[index].x, result[index].y)
        result[index] = Object.assign({}, result[index], position)
        placed.push(result[index])
    }
    return result
}

// Move a monitor by whole steps with the arrow keys, then let `snap` finish
// the job. Dragging with the mouse is fine for a rough arrangement and useless
// for "one of these is twelve pixels low"; the keyboard is what that needs.
//
// `step` is in *logical* pixels, the same units as x and y, so a step is the
// same distance whatever the monitor's scale is - a nudge that moved further
// on a scaled screen than on an unscaled one would be its own puzzle.
//
// The snap runs after the step and not instead of it: without it a monitor
// nudged towards its neighbour stops one step short of the edge and stays
// there, which is exactly the misalignment the arrow keys exist to remove.
// With it, the last step before an edge lands *on* the edge.
function nudge(monitors, name, dx, dy, step, threshold) {
    const target = monitors.find(monitor => monitor.name === name)
    if (!target) return null
    const size = Math.abs(Math.round(Number(step))) || 1
    const moveX = Math.sign(Number(dx) || 0) * size
    const moveY = Math.sign(Number(dy) || 0) * size
    if (moveX === 0 && moveY === 0) return { x: Math.round(target.x), y: Math.round(target.y) }
    return snap(monitors, name, Math.round(target.x) + moveX, Math.round(target.y) + moveY,
                Math.max(0, Number(threshold) || 0))
}

// True when enabled monitors overlap. Hyprland does not move them: explicit
// positions are kept as given, a warning is shown, and input lands on the
// wrong screen - which is why the page refuses to apply such a layout and
// every move goes through placeApart.
function overlapping(monitors) {
    const enabled = monitors.filter(monitor => !monitor.disabled)
    for (let i = 0; i < enabled.length; ++i) {
        for (let j = i + 1; j < enabled.length; ++j) {
            const a = enabled[i], b = enabled[j]
            const sa = logicalSize(a), sb = logicalSize(b)
            if (a.x < b.x + sb.width && b.x < a.x + sa.width && a.y < b.y + sb.height && b.y < a.y + sa.height) return true
        }
    }
    return false
}

// Laptop panels (for the lid).
function isInternal(name) {
    return /^(eDP|LVDS|DSI)/.test(String(name))
}

// Lid closed with "screen off": disable the internal panel when another
// monitor is on (windows move there), otherwise only switch it off (dpms) so
// the session keeps an output.
function lidPlan(monitors, internalName) {
    if (!monitors.some(monitor => monitor.name === internalName)) return "none"
    return monitors.some(monitor => monitor.name !== internalName && !monitor.disabled) ? "disable" : "dpms"
}

// The target layout while the lid is closed: the internal panel is disabled
// whenever another monitor is enabled, and enabled again when it is the last one.
function lidAdjusted(monitors, internalName, lidClosed) {
    if (!lidClosed || !internalName) return monitors
    const plan = lidPlan(monitors.map(monitor => monitor.name === internalName ? Object.assign({}, monitor, { disabled: false }) : monitor), internalName)
    if (plan === "none") return monitors
    return update(monitors, internalName, { disabled: plan === "disable" })
}

// Persistence: saved settings per monitor name.
function toSaved(monitors) {
    const result = { version: 1, monitors: {} }
    for (const monitor of monitors) {
        result.monitors[monitor.name] = {
            description: monitor.description,
            width: monitor.width, height: monitor.height, refresh: monitor.refresh,
            x: monitor.x, y: monitor.y, scale: monitor.scale, transform: monitor.transform,
            vrr: monitor.vrr, disabled: monitor.disabled
        }
    }
    return result
}

// The saved file with the positions `applySaved` had to correct (spread),
// and nothing else touched: entries of monitors that are not connected now
// stay as they are, which is why this does not go through `toSaved`. Null
// when the file already says what the layout says.
function repairSaved(saved, monitors) {
    if (!saved || saved.version !== 1 || !saved.monitors) return null
    let changed = false
    const entries = {}
    for (const name in saved.monitors) entries[name] = Object.assign({}, saved.monitors[name])
    for (const monitor of monitors) {
        const entry = entries[monitor.name]
        if (!entry || monitor.disabled) continue
        if (Number(entry.x) === monitor.x && Number(entry.y) === monitor.y) continue
        entry.x = monitor.x
        entry.y = monitor.y
        changed = true
    }
    return changed ? { version: 1, monitors: entries } : null
}

// Monitors with saved settings applied (only connected ones; never disables
// every monitor).
function applySaved(monitors, saved) {
    if (!saved || saved.version !== 1 || !saved.monitors) return monitors
    const next = monitors.map(monitor => {
        const entry = saved.monitors[monitor.name]
        if (!entry) return monitor
        const mode = monitor.modes.find(item => item.width === entry.width && item.height === entry.height
                                          && Math.abs(item.refresh - entry.refresh) < 0.5)
        return Object.assign({}, monitor, {
            width: mode ? mode.width : monitor.width,
            height: mode ? mode.height : monitor.height,
            refresh: mode ? mode.refresh : monitor.refresh,
            x: Number(entry.x) || 0, y: Number(entry.y) || 0,
            // A custom scale is allowed, within what a monitor can be run at;
            // the old whitelist appended the value to itself before looking
            // it up and so refused nothing.
            scale: validScale(entry.scale) ? round2(entry.scale) : monitor.scale,
            transform: [0, 1, 2, 3].indexOf(entry.transform) >= 0 ? entry.transform : 0,
            vrr: [0, 1, 2].indexOf(entry.vrr) >= 0 ? entry.vrr : 0,
            disabled: entry.disabled === true
        })
    })
    // Spread, because the positions in the file may have been computed from
    // widths that were wrong (effectiveScale), and because a mode or scale
    // changed by hand in the file changes a size under its neighbours.
    return enabledCount(next) > 0 ? spread(next) : monitors
}
