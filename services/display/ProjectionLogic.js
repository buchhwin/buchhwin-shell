.pragma library
.import "DisplayLogic.js" as Display
.import "../hypr/HyprCommands.js" as Commands

// The display switcher (Super+Shift+P, the projector key): what Windows calls
// "Project" and KDE puts behind Meta+P - the laptop panel only, the same
// picture on every screen, one desktop over all of them, or the external
// screens only. A choice is laid over the layout the shell would apply
// anyway (DisplayService: the saved monitors.json, the lid), so it is never
// written to the file: it lasts while the same monitors are connected, and a
// monitor plugged in or taken away ends it - the projector unplugged puts the
// laptop's own layout back, which is also the way out of "External only" on
// a screen that shows nothing. Settings > Displays' "Mirror" is the one that
// is kept. Unit tested (ProjectionTest).

// In the order Windows shows them. The glyphs say what a choice is, so they
// stay here with it, as a mode's glyph stays with ProfileLogic.
var CHOICES = [
    { value: "internal", label: "Laptop only", glyph: "\u{f0322}" },
    { value: "duplicate", label: "Duplicate", glyph: "\u{f0191}" },
    { value: "extend", label: "Extend", glyph: "\u{f037a}" },
    { value: "external", label: "External only", glyph: "\u{f0379}" }
]

function list(value) {
    return Array.isArray(value) ? value : []
}

function choice(mode) {
    return CHOICES.find(item => item.value === mode) || null
}

function label(mode) {
    const found = choice(mode)
    return found ? found.label : ""
}

function glyph(mode) {
    const found = choice(mode)
    return found ? found.glyph : ""
}

// The laptop panel among the monitors, or null. `internalName` is the one
// DisplayService knows (Display.isPanel: "" on a machine without one).
function panelOf(monitors, internalName) {
    return list(monitors).find(monitor => Display.isPanel(monitor.name, internalName)) || null
}

function externals(monitors, internalName) {
    return list(monitors).filter(monitor => !Display.isPanel(monitor.name, internalName))
}

// What the monitors are doing now, as one of the four: a mirror anywhere is
// "duplicate"; with a panel and a screen beside it, only the one or only the
// other on is "internal" or "external"; everything else is "extend". The
// lid's panel off at a desk reads as "external", which is what it is.
function current(monitors, internalName) {
    const all = list(monitors)
    if (all.some(monitor => !monitor.disabled && Display.isMirror(monitor))) return "duplicate"
    const panel = panelOf(all, internalName)
    const outside = externals(all, internalName)
    if (panel && outside.length) {
        const outsideOn = outside.filter(monitor => !monitor.disabled)
        if (panel.disabled && outsideOn.length) return "external"
        if (!panel.disabled && !outsideOn.length) return "internal"
    }
    return "extend"
}

// Whether a choice can be made with these monitors. With one monitor there
// is nothing to choose. "Laptop only" and "External only" need the panel
// and a screen beside it, and "Laptop only" an open lid: behind a shut lid
// it would leave every screen dark. "Duplicate" needs two screens that can
// show something - a panel behind a shut lid is not one.
function available(mode, monitors, internalName, lidClosed) {
    const all = list(monitors)
    if (all.length < 2) return false
    const panel = panelOf(all, internalName)
    const outside = externals(all, internalName)
    if (mode === "internal") return !!panel && outside.length > 0 && lidClosed !== true
    if (mode === "external") return !!panel && outside.length > 0
    if (mode === "duplicate") return all.filter(monitor => !(lidClosed === true && panel && monitor.name === panel.name)).length >= 2
    return mode === "extend"
}

// The choices the switcher shows: all four on a laptop, "Duplicate" and
// "Extend" on a machine without a panel, each with whether it can be made.
function choices(monitors, internalName, lidClosed) {
    const panel = panelOf(monitors, internalName)
    return CHOICES.filter(item => panel || (item.value !== "internal" && item.value !== "external"))
        .map(item => Object.assign({}, item, { enabled: available(item.value, monitors, internalName, lidClosed) }))
}

// The next choice that can be made after `mode`, round: the projector key
// pressed again while the switcher is open moves on, as Windows' does.
function next(mode, items) {
    const usable = list(items).filter(item => item.enabled !== false)
    if (!usable.length) return String(mode || "")
    const at = usable.findIndex(item => item.value === mode)
    return usable[(at + 1) % usable.length].value
}

// Whether two monitors cover each other, in the layout's logical pixels.
function covers(a, b) {
    const sa = Display.logicalSize(a), sb = Display.logicalSize(b)
    return a.x < b.x + sb.width && b.x < a.x + sa.width && a.y < b.y + sb.height && b.y < a.y + sa.height
}

// Monitors that have a place in the layout again (switched back on, or no
// longer a mirror) keep their own place where it is free and go to the end
// of the layout where it is not (Display.placeAfter): the nearest way out
// could put one first in the monitor order, and every block of workspaces
// would move one screen on.
function placeBack(monitors, names) {
    let result = list(monitors)
    for (const name of list(names)) {
        const me = result.find(monitor => monitor.name === name)
        if (!me || !Display.shown(me)) continue
        if (!result.some(other => other.name !== name && Display.shown(other) && covers(me, other))) continue
        result = Display.update(result, name, Display.placeAfter(result, name))
    }
    return result
}

// Which monitor "Duplicate" copies: the laptop panel while its lid is open,
// else the screen with the focus, else the first from the left.
function sourceFor(monitors, internalName, lidClosed, focusedName) {
    const candidates = list(monitors).filter(monitor => !monitor.disabled
        && !(lidClosed === true && Display.isPanel(monitor.name, internalName)))
    const panel = candidates.find(monitor => Display.isPanel(monitor.name, internalName))
    if (panel) return panel.name
    const focused = candidates.find(monitor => monitor.name === focusedName)
    if (focused) return focused.name
    const sorted = candidates.slice().sort((a, b) => a.x - b.x || a.y - b.y || String(a.name).localeCompare(String(b.name)))
    return sorted.length ? sorted[0].name : ""
}

// The layout a choice makes of `base` (the saved layout, or the monitors as
// they are), as { list, touched }, or null when the choice cannot be made
// (`available`). Every monitor starts on and on its own; then:
//   extend    - all of them, side by side (one coming back goes at the end)
//   duplicate - every other screen mirrors the source (`sourceFor`)
//   internal  - the screens beside the panel off
//   external  - the panel off
// A panel behind a shut lid is left on here: the lid's adjustment comes
// after this (DisplayLogic.savedTarget) and takes it off. `touched` names
// the monitors the choice switched off or made a mirror, so that taking it
// back (`undo`) can put exactly those back.
function target(base, mode, internalName, lidClosed, focusedName) {
    const all = list(base)
    if (!available(mode, all, internalName, lidClosed)) return null
    const reshown = all.filter(monitor => !Display.shown(monitor)).map(monitor => monitor.name)
    const on = all.map(monitor => Object.assign({}, monitor, { disabled: false, mirror: "" }))
    const off = monitor => Object.assign({}, monitor, { disabled: true })
    let result
    if (mode === "internal") {
        result = on.map(monitor => Display.isPanel(monitor.name, internalName) ? monitor : off(monitor))
    } else if (mode === "external") {
        result = on.map(monitor => Display.isPanel(monitor.name, internalName) ? off(monitor) : monitor)
    } else if (mode === "duplicate") {
        const source = sourceFor(on, internalName, lidClosed, focusedName)
        result = on.map(monitor => monitor.name === source || (lidClosed === true && Display.isPanel(monitor.name, internalName))
                        ? monitor : Object.assign({}, monitor, { mirror: source }))
    } else {
        result = on
    }
    result = placeBack(result, reshown)
    const touched = result.filter(monitor => {
        const before = all.find(item => item.name === monitor.name)
        return (monitor.disabled && !(before && before.disabled))
            || (Display.isMirror(monitor) && !(before && Display.isMirror(before)))
    }).map(monitor => monitor.name)
    return { list: result, touched: touched }
}

// Where the monitors a choice is about to touch stand now, by name ({ x, y }),
// added to `known` - a place already known (from an earlier choice) is kept.
// Hyprland moves a mirror onto its source, so a screen that stops mirroring
// no longer says where it stood; without this "Duplicate" then "Extend" put
// it after the others, and the blocks of workspaces swapped screens. A
// monitor that is off or a mirror already has no place to keep.
function placesOf(monitors, names, known) {
    const result = Object.assign({}, known || {})
    for (const name of list(names)) {
        const me = list(monitors).find(monitor => monitor.name === name)
        if (me && Display.shown(me) && !result[name]) result[name] = { x: Math.round(me.x), y: Math.round(me.y) }
    }
    return result
}

// The monitors as they would be without a choice: the ones it touched on
// again and on their own (back at their place, or at the end of the layout
// where that is taken). `places` (optional, `placesOf`) is where they stood
// before the choice. What the saved file and the lid then make of them is
// theirs (DisplayService.applySavedIfNeeded).
function undo(monitors, touched, places) {
    const names = list(touched).map(String)
    if (!names.length) return list(monitors)
    const before = places || {}
    const result = list(monitors).map(monitor => {
        if (names.indexOf(monitor.name) < 0) return monitor
        const place = before[monitor.name]
        return Object.assign({}, monitor, { disabled: false, mirror: "" },
                             place && isFinite(place.x) && isFinite(place.y) ? { x: place.x, y: place.y } : {})
    })
    return placeBack(result, names)
}

// The layout to apply (DisplayService.layoutTarget): the saved one over the
// monitors as they would be without the switcher's choice - `held` is what
// the choices so far touched and where those stood ({ touched, places },
// `undo`) -, with the choice `mode` laid over it ("" for none) and the lid's
// adjustment after both (Display.savedTarget). `context` is { internalName,
// lidClosed, lidKnown, focused }. Display.savedTarget's { base, target, held }
// with `touched`, the monitors `mode` switches off or makes a mirror; null
// when there is nothing to apply or the choice cannot be made.
function plan(live, saved, mode, held, context) {
    const memory = held || {}
    const touched = list(memory.touched)
    const base = touched.length ? undo(live, touched, memory.places) : list(live)
    const ctx = context || {}
    let made = []
    const project = mode ? (monitors => {
        const result = target(monitors, mode, ctx.internalName, ctx.lidClosed, ctx.focused)
        made = result ? result.touched : []
        return result ? result.list : null
    }) : null
    const result = Display.savedTarget(base, saved, ctx.internalName, ctx.lidClosed, ctx.lidKnown,
                                       { project: project, force: touched.length > 0 })
    return result ? Object.assign({}, result, { touched: made }) : null
}

// A screen on, with a place of its own, and not FALLBACK - the output
// Hyprland makes for itself while no real screen is on.
function real(monitor) {
    return !!monitor && Display.shown(monitor) && monitor.name !== "FALLBACK"
}

// A layout in the steps Hyprland can take it in, as a list of one or two
// lists of monitors to send - [] for a layout with no real screen on, which
// is never sent. Hyprland applies a layout in one pass over the monitors,
// in the order it made them, switching each on or off as it comes to it
// (0.56, MonitorRuleManager.ensureMonitorStatus). So
//   - where every screen that shows something now goes off or becomes a
//     mirror, there is a moment with no screen at all: "Laptop only" to
//     "External only" switched the panel off before the projector came on,
//     and Hyprland fell back to an output of its own and moved every
//     workspace there and back;
//   - a mirror of a screen that is off now mirrors nothing: its source is
//     not on yet when the mirror is set, and "External only" to "Duplicate"
//     left both screens side by side.
// In those two cases the screens that come on (`up`: off or a mirror now, a
// place of their own in the layout) go first, alone and at their places -
// at the end of the layout where a screen still on stands there -, and the
// whole layout once they are read back on (DisplayService.send).
function steps(live, layout) {
    const now = list(live)
    const next = list(layout)
    if (!next.some(real)) return []
    const before = name => now.find(monitor => monitor.name === name) || null
    const up = next.filter(monitor => Display.shown(monitor) && !Display.shown(before(monitor.name)))
    const stays = next.some(monitor => Display.shown(monitor) && Display.shown(before(monitor.name)))
    const lateSource = next.some(monitor => !monitor.disabled && Display.isMirror(monitor) && !Display.shown(before(monitor.mirror)))
    if (!up.length || (stays && !lateSource)) return [next]
    const names = up.map(monitor => monitor.name)
    const first = placeBack(now.map(monitor => up.find(item => item.name === monitor.name) || monitor), names)
    return [first.filter(monitor => names.indexOf(monitor.name) >= 0), next]
}

// Whether every monitor named is on and shown now: the first step is in.
function cameUp(monitors, names) {
    return list(names).every(name => Display.shown(list(monitors).find(monitor => monitor.name === name) || null))
}

// The screens a layout takes away, by name: shown now, and a mirror of
// another or off in it - the ones whose workspaces Hyprland hands to the
// screens left (DisplayService.mirrorViews).
function leaving(live, layout) {
    const now = list(live)
    return list(layout).filter(monitor => !Display.shown(monitor)
                                   && Display.shown(now.find(item => item.name === monitor.name) || null))
        .map(monitor => monitor.name)
}

// The screens that stay on through a layout, by name: shown now and in it
// (DisplayService.stayViews).
function staying(live, layout) {
    const now = list(live)
    return list(layout).filter(monitor => Display.shown(monitor)
                                   && Display.shown(now.find(item => item.name === monitor.name) || null))
        .map(monitor => monitor.name)
}

// ---- What Hyprland is sent ----------------------------------------------
//
// One request per layout, in each dialect, made here and nowhere else: the
// switcher, the saved layout, the lid, and Settings > Displays' apply and
// revert all send what `layoutCommand` makes of their monitors.
//
// The conf dialect: the monitor keywords in one `hyprctl --batch`. Hyprland
// takes a monitor keyword at once but applies the rules only before it next
// draws a frame (0.56: the keyword schedules MonitorRuleManager's reload,
// which runs from the render's pre-checks). With the laptop panel off and
// nothing moving on the other screen nothing was drawn, and "External only"
// then "Extend" or "Laptop only" left the panel off. The last keyword
// carries hyprctl's refresh flag (`r/`, as `hyprctl -r` does for one
// command), which redraws every screen after it. The Lua dialect's
// hl.monitor refreshes the monitors itself.
function confCommand(entries) {
    const lines = list(entries).map(entry => monitorCommand(entry).legacy).filter(line => line.length > 0)
    if (lines.length) lines[lines.length - 1] = "r/" + lines[lines.length - 1]
    return lines.join(" ; ")
}

// The Lua dialect: an hl.monitor call per monitor, in one eval. Each says
// whether it is on and what it mirrors (`monitorCommand`): hl.monitor keeps
// what an earlier call said and a new one leaves out.
function luaCommand(entries) {
    return list(entries).map(entry => monitorCommand(entry).lua).join("\n")
}

// Both, as HyprCompat.configure takes them.
function layoutCommand(entries) {
    return { legacy: confCommand(entries), legacyEmpty: [], lua: luaCommand(entries) }
}

// The monitors that are connected, as one string: a choice lasts while it
// stays the same. Names and descriptions, so another screen on the same
// connector is a change too; on or off is not (the lid's panel is listed
// either way).
function setKey(monitors) {
    return list(monitors).map(monitor => String(monitor.name) + "\u0001" + String(monitor.description || ""))
        .sort().join("\n")
}

// The monitor rule for one monitor, in both dialects (HyprCommands.monitor
// for a monitor of its own). A mirror's rule names its source; its position
// is "auto", because Hyprland puts a mirror at its source's place, and a
// mirror whose source is not there (gone a moment ago) then still lands
// beside the others rather than on top of one. In Lua it says `disabled =
// false` too: hl.monitor keeps an earlier call's "off" (Commands.monitor), and
// a screen that "Laptop only" switched off would stay dark as a mirror.
function monitorCommand(entry) {
    if (entry.disabled || !Display.isMirror(entry)) return Commands.monitor(entry)
    const name = Commands.checkWord(entry.name)
    const source = Commands.checkWord(entry.mirror)
    const mode = Math.round(entry.width) + "x" + Math.round(entry.height) + "@" + Number(entry.refresh).toFixed(2)
    const scale = Math.round(Number(entry.scale) * 100) / 100
    return {
        legacyEmpty: [],
        legacy: "keyword monitor " + name + "," + mode + ",auto," + scale + ",transform," + Number(entry.transform)
            + ",vrr," + Number(entry.vrr) + ",mirror," + source,
        lua: "hl.monitor({ output = " + Commands.luaString(name) + ", mode = " + Commands.luaString(mode)
            + ", position = \"auto\", scale = " + scale + ", transform = " + Number(entry.transform)
            + ", vrr = " + Number(entry.vrr) + ", disabled = false, mirror = " + Commands.luaString(source) + " })"
    }
}

// The names of the monitors that mirror another, sorted: what
// HyprlandService's blocks of workspaces leave out.
function mirrorNames(monitors) {
    return list(monitors).filter(monitor => !monitor.disabled && Display.isMirror(monitor)).map(monitor => monitor.name).sort()
}
