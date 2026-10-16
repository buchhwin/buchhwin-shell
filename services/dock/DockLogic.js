.pragma library
.import "../hypr/HiddenWindows.js" as Hidden

// The dock (shell/dock/Dock.qml, services/DockService.qml): pinned apps - the
// launcher's pins - and the apps that have windows, along one edge of a
// screen. Everything here is arithmetic on plain objects, so the tests can
// ask it everything the surface and the service decide.

var POSITIONS = ["bottom", "left", "right"]
var SPANS = ["fit", "full"]
var VISIBILITY = ["always", "intellihide", "hidden"]
var ICON_SIZES = [40, 48, 56, 64]
var MARGINS = [0, 4, 8, 16]
// Dots under an app: one per window, up to this many.
var MAX_DOTS = 3
// The smallest an icon is fitted down to when the edge runs out of room.
var MIN_ICON = 20

// Hyprland's events after which a window may have come over the dock or left
// it. There is no event for a floating window moved or resized by hand: that
// is what the slow poll is for (needsPoll).
var COVER_EVENTS = ["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode",
    "fullscreen", "workspace", "workspacev2", "focusedmon", "focusedmonv2", "activespecial",
    "activespecialv2", "activewindowv2", "pin", "togglegroup", "moveintogroup", "moveoutofgroup",
    "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"]

function lower(text) { return String(text || "").toLowerCase() }

// ---- settings ------------------------------------------------------------------
// The screens a dock is on, from the stored comma list: empty is every screen,
// and a list that names none of the screens there are is every screen too -
// a monitor that is gone must not leave the dock nowhere.
function screensFor(stored, names) {
    const all = Array.prototype.slice.call(names || [])
    const wanted = String(stored || "").split(",").map(part => part.trim()).filter(part => part.length)
    const shown = all.filter(name => wanted.indexOf(name) >= 0)
    return shown.length ? shown : all
}

// A screen chip ticked or unticked: the new stored list, "" when that is every
// screen, null when it would take the last one away.
function toggleScreen(stored, name, all) {
    const names = Array.prototype.slice.call(all || [])
    const current = screensFor(stored, names)
    const next = current.indexOf(name) >= 0 ? current.filter(item => item !== name)
        : names.filter(item => item === name || current.indexOf(item) >= 0)
    if (!next.length) return null
    return next.length === names.length ? "" : next.join(",")
}

// A value for `dock setOption KEY VALUE`, or null when it is not one.
function optionValue(key, value) {
    const text = String(value === undefined || value === null ? "" : value).trim()
    switch (key) {
    case "enabled": case "showRunning": case "magnification":
        return text === "true" ? true : text === "false" ? false : null
    case "visibility": return VISIBILITY.indexOf(text) >= 0 ? text : null
    case "position": return POSITIONS.indexOf(text) >= 0 ? text : null
    case "span": return SPANS.indexOf(text) >= 0 ? text : null
    case "iconSize": return ICON_SIZES.indexOf(Number(text)) >= 0 && /^\d+$/.test(text) ? Number(text) : null
    case "margin": return MARGINS.indexOf(Number(text)) >= 0 && /^\d+$/.test(text) ? Number(text) : null
    // Output names (eDP-1, DP-8, HDMI-A-1), comma-separated; "" is every screen.
    case "screens": return /^[\w.:-]*(,[\w.:-]+)*$/.test(text) ? text : null
    }
    return null
}

// ---- windows and apps ------------------------------------------------------------
function lastSegment(id) {
    const parts = String(id || "").split(".")
    return parts[parts.length - 1]
}

// Whether a desktop entry is the app of a window class. The class is what a
// window says it is (Wayland's app id, or X11's class): the entry's id
// (org.kde.dolphin), its StartupWMClass (crx_<app> for a web app under
// XWayland, Code for VS Code), or the last part of a reverse-DNS name on
// either side (dolphin, firefox for org.mozilla.firefox).
function entryMatches(entry, cls) {
    if (!entry || !cls) return false
    const name = lower(cls)
    const id = lower(entry.id)
    const wm = lower(entry.startupClass)
    if (!name.length || !id.length) return false
    return name === id || (wm.length > 0 && name === wm)
        || name === lower(lastSegment(entry.id)) || id === lower(lastSegment(cls))
}

// The app a window class belongs to: a pinned one first, in the pins' order
// (two desktop files for one browser attach to the one that is pinned), then
// what the lookup finds, else the class itself.
function resolve(cls, pins, lookup) {
    const name = String(cls || "")
    if (!name.length) return null
    for (const pin of pins || [])
        if (entryMatches(pin, name)) return { key: "app:" + pin.id, entry: pin }
    const entry = typeof lookup === "function" ? lookup(name) : null
    if (entry && entry.id) return { key: "app:" + entry.id, entry: entry }
    return { key: "class:" + lower(name), entry: null }
}

// The windows a dock shows: none of the shell's helpers (HiddenWindows.js)
// and nothing without a class.
function visibleWindows(windows) {
    return Array.prototype.slice.call(windows || []).filter(window => window
        && String(window.appClass || "").length > 0
        && !Hidden.isHiddenClass(window.appClass)
        && String(window.workspaceName || "") !== Hidden.workspace)
}

// The dock's apps: the pins in their order, then - with `showRunning` - the
// apps that have windows, in the order their first window appeared (`seq`),
// so an app does not jump about when another one is focused or opened.
// Each: { key, entryId, name, icons, pinned, pinIndex, windows, running,
// active, urgent, count }. `windows` are ordered by `seq` as well.
function build(pins, windows, lookup, options) {
    const showRunning = !options || options.showRunning !== false
    const items = []
    const byKey = {}
    Array.prototype.slice.call(pins || []).forEach((pin, index) => {
        if (!pin || !pin.id || byKey["app:" + pin.id]) return
        const item = { key: "app:" + pin.id, entryId: pin.id, name: pin.name || pin.id,
                       icons: [pin.icon || "", pin.id], pinned: true, pinIndex: index, windows: [],
                       // What is stored for it: the id, or a default's token (@terminal).
                       pin: pin.pin || pin.id, special: pin.special || "", glyph: pin.glyph || "" }
        byKey[item.key] = item
        items.push(item)
    })
    const sorted = visibleWindows(windows).slice().sort((a, b) => (a.seq || 0) - (b.seq || 0))
    for (const window of sorted) {
        const found = resolve(window.appClass, pins, lookup)
        let item = byKey[found.key]
        if (!item) {
            if (!showRunning) continue
            const entry = found.entry
            item = { key: found.key, entryId: entry ? entry.id : "",
                     name: entry ? (entry.name || entry.id) : window.appClass,
                     icons: [entry ? entry.icon || "" : "", window.appClass], pinned: false, pinIndex: -1, windows: [],
                     pin: entry ? entry.id : "", special: "", glyph: "" }
            byKey[item.key] = item
            items.push(item)
        }
        item.windows.push({ address: window.address, workspace: window.workspace, monitor: window.monitor,
                            seq: window.seq || 0, activated: window.activated === true, urgent: window.urgent === true })
    }
    for (const item of items) {
        item.running = item.windows.length > 0
        item.active = item.windows.some(window => window.activated)
        item.urgent = item.windows.some(window => window.urgent)
        item.count = item.windows.length
    }
    return items
}

// What a click on an app does: start it (no window), focus its window used
// last (the app is not the active one), the next of its windows (it is, and
// has more than one), or nothing. The next is by when they appeared: the
// order of use would only ever swap the last two.
function clickTarget(item, activeAddress, mru) {
    if (!item) return { action: "none", address: "" }
    const windows = item.windows || []
    if (!windows.length) return { action: item.entryId ? "launch" : "none", address: "" }
    const active = windows.findIndex(window => window.address === activeAddress)
    if (active >= 0) {
        if (windows.length < 2) return { action: "none", address: "" }
        return { action: "focus", address: windows[(active + 1) % windows.length].address }
    }
    for (const address of mru || [])
        if (windows.some(window => window.address === address)) return { action: "focus", address: address }
    return { action: "focus", address: windows[0].address }
}

// The desktop action that opens a new window, when the entry has one (Brave,
// Chrome: "new-window"; never the private one), else "".
function newWindowAction(actions) {
    const list = Array.prototype.slice.call(actions || [])
    const found = list.find(action => action && /^new[-_ ]?window$/i.test(String(action.id || "")))
    return found ? found.id : ""
}

// The rows of an app's menu, top to bottom. Kinds: window (one per window, up
// to `maxWindows`, then a "more"), new, action (desktop actions but the new
// window one), pin/unpin, close.
function menuRows(item, actions, pinnedFull, maxWindows) {
    if (!item) return []
    const rows = []
    const windows = item.windows || []
    const shown = Math.max(0, Math.min(windows.length, maxWindows === undefined ? windows.length : maxWindows))
    for (let index = 0; index < shown; ++index)
        rows.push({ kind: "window", address: windows[index].address, workspace: windows[index].workspace })
    if (windows.length > shown) rows.push({ kind: "more", count: windows.length - shown })
    if (item.special === "settings") {
        rows.push({ kind: "unpin" })
        return rows
    }
    if (item.entryId) {
        rows.push({ kind: "new" })
        const skip = newWindowAction(actions)
        for (const action of Array.prototype.slice.call(actions || []))
            if (action && action.id !== skip) rows.push({ kind: "action", id: action.id, name: action.name || action.id })
        rows.push(item.pinned ? { kind: "unpin" } : { kind: "pin", enabled: !pinnedFull })
    }
    if (windows.length) rows.push({ kind: "close", count: windows.length })
    return rows
}

// ---- covered: intellihide ------------------------------------------------------------
function validRect(rect) {
    return rect && isFinite(rect.x) && isFinite(rect.y) && rect.width > 0 && rect.height > 0
}

function overlaps(a, b, slack) {
    const s = Math.max(0, Number(slack) || 0)
    return a.x < b.x + b.width + s && a.x + a.width > b.x - s
        && a.y < b.y + b.height + s && a.y + a.height > b.y - s
}

// Whether a window counts on a dock's screen: on that monitor, on the
// workspace it shows (or the special one open over it, or pinned to all), and
// one of the windows a user sees.
function onView(window, view) {
    if (!window || !view || window.monitor !== view.monitor) return false
    if (window.hidden === true || window.mapped === false) return false
    if (Hidden.isHiddenClass(window.appClass) || String(window.workspaceName || "") === Hidden.workspace) return false
    return window.pinned === true || window.workspace === view.workspace
        || (String(view.special || "").length > 0 && window.workspaceName === view.special)
}

// Intellihide: a window touches the dock's body (global coordinates, the dock
// as shown, plus `slack`). A window without a geometry yet does not count -
// unknown is not covered, as for fullscreen (FullscreenLogic).
function covered(body, windows, view, slack) {
    if (!validRect(body)) return false
    for (const window of windows || []) {
        if (!onView(window, view)) continue
        const at = window.at, size = window.size
        if (!at || !size || at.length < 2 || size.length < 2) continue
        const rect = { x: Number(at[0]), y: Number(at[1]), width: Number(size[0]), height: Number(size[1]) }
        if (validRect(rect) && overlaps(rect, body, slack)) return true
    }
    return false
}

// Floating windows move without telling anyone; while one is on a dock's
// workspace the service asks again every so often.
function needsPoll(windows, views) {
    for (const view of views || [])
        for (const window of windows || [])
            if (window && window.floating === true && onView(window, view)) return true
    return false
}

// Shown or not, for one dock. Fullscreen hides it whatever else; a drag, its
// menu and the keyboard keep it; "always" shows it; the pointer at the edge
// (`pointer`: held there long enough, or still on the dock) and the key show
// it; intellihide shows it while no window touches it.
function wantRevealed(state) {
    const s = state || {}
    if (!s.enabled || s.fullscreen) return false
    if (s.dragging || s.menuOpen || s.keyboard) return true
    if (s.mode === "always") return true
    if (s.pointer || s.hotkey) return true
    return s.mode === "intellihide" ? !s.covered : false
}

// Where input lands: nowhere under a fullscreen window, the body while shown,
// a thin strip at the edge while hidden - unless the dock reserves its room,
// where nothing else could be under it anyway.
function maskKind(state) {
    const s = state || {}
    if (!s.active) return "none"
    if (s.revealed) return "body"
    return s.reserves ? "none" : "strip"
}

// The screen the key shows the dock on: the focused one when it has a dock,
// else the first that does.
function revealTarget(focused, docks) {
    const list = Array.prototype.slice.call(docks || [])
    if (list.indexOf(focused) >= 0) return focused
    return list.length ? list[0] : ""
}

// ---- geometry ------------------------------------------------------------------
function vertical(edge) { return edge === "left" || edge === "right" }

// The icon size that fits: the setting, or smaller when `count` icons do not
// fit along `room` (never below MIN_ICON).
function fit(count, icon, gap, room, pad) {
    const n = Math.max(0, Math.round(count || 0))
    if (n === 0) return icon
    const free = room - 2 * pad - (n - 1) * gap
    return Math.max(MIN_ICON, Math.min(icon, Math.floor(free / n)))
}

// Where each icon starts along the body, its size scaled by `scales` (all 1
// without magnification), and the body's length. `sep` is the index of the
// first unpinned app (-1: none), which gets a separator's room before it.
function layout(count, icon, gap, scales, pad, sep, sepRoom) {
    const offsets = []
    const sizes = []
    let at = pad
    for (let index = 0; index < count; ++index) {
        if (index === sep && index > 0) at += sepRoom
        const size = icon * (scales && scales.length > index ? scales[index] : 1)
        offsets.push(at)
        sizes.push(size)
        at += size + (index < count - 1 ? gap : 0)
    }
    return { offsets: offsets, sizes: sizes, length: (count > 0 ? at : 0) + pad }
}

// Magnification: each icon's scale for a pointer at `pointer` along the dock
// (-1: away), from the icons' resting centres, falling off over `reach`.
function magnify(pointer, centres, peak, reach) {
    const list = Array.prototype.slice.call(centres || [])
    if (!(pointer >= 0) || !(reach > 0) || !(peak > 1)) return list.map(() => 1)
    return list.map(centre => {
        const distance = Math.abs(pointer - centre)
        if (distance >= reach) return 1
        const weight = (Math.cos(Math.PI * distance / reach) + 1) / 2
        return 1 + (peak - 1) * weight
    })
}

// The dock on one edge. `m`: { icon, pad, gap, margin, headroom, windowGap,
// strip, count, room (the surface's length along the edge), sep, sepRoom }.
// Returns the surface's thickness, the zone it reserves when it does, the
// fitted icon size and, in the surface's own coordinates, the body and the
// strip at the edge. The thickness follows the settings only - never the
// number of apps - so the surface never changes size while mapped (pitfall 57).
function geometry(edge, m, reserve) {
    const side = POSITIONS.indexOf(edge) >= 0 ? edge : "bottom"
    const across = m.icon + 2 * m.pad
    const thickness = m.margin + across + m.headroom
    const icon = fit(m.count, m.icon, m.gap, m.room, m.pad)
    const along = layout(m.count, icon, m.gap, null, m.pad, m.sep === undefined ? -1 : m.sep, m.sepRoom || 0).length
    const length = Math.min(m.room, Math.max(along, 2 * m.pad))
    const start = Math.round((m.room - length) / 2)
    // Across: from the screen edge in, the margin, then the body.
    const near = m.margin
    const body = side === "bottom" ? { x: start, y: thickness - near - across, width: length, height: across }
        : side === "left" ? { x: near, y: start, width: across, height: length }
        : { x: thickness - near - across, y: start, width: across, height: length }
    const strip = side === "bottom" ? { x: start, y: thickness - m.strip, width: length, height: m.strip }
        : side === "left" ? { x: 0, y: start, width: m.strip, height: length }
        : { x: thickness - m.strip, y: start, width: m.strip, height: length }
    // The body and the margin band down to the edge: the pointer resting on
    // the screen edge under the dock is on it.
    const hit = side === "bottom" ? { x: start, y: body.y, width: length, height: thickness - body.y }
        : side === "left" ? { x: 0, y: start, width: body.x + across, height: length }
        : { x: body.x, y: start, width: thickness - body.x, height: length }
    return {
        edge: side, vertical: vertical(side), thickness: thickness, across: across, icon: icon,
        length: length, start: start, body: body, strip: strip, hit: hit,
        // The room the windows leave: the body and a margin on each side of
        // it, less the gap Hyprland puts back (NotchLogic.reserveHeight).
        zone: reserve ? Math.max(0, 2 * m.margin + across - m.windowGap) : 0,
        // How far the dock reaches into the screen, for the OSD above it.
        reach: m.margin + across
    }
}

// The body in global coordinates: the surface's body moved by where the
// surface sits - its screen, and what the compositor laid it against (a bar
// on the same edge, or one on the sides it spans).
function globalRect(rect, screen, offsets, thickness, edge) {
    if (!validRect(rect) || !screen) return null
    const o = offsets || {}
    const x0 = screen.x + (o.left || 0)
    const y0 = screen.y + (o.top || 0)
    if (edge === "bottom")
        return { x: x0 + rect.x, y: screen.y + screen.height - (o.bottom || 0) - thickness + rect.y,
                 width: rect.width, height: rect.height }
    if (edge === "right")
        return { x: screen.x + screen.width - (o.right || 0) - thickness + rect.x, y: y0 + rect.y,
                 width: rect.width, height: rect.height }
    return { x: x0 + rect.x, y: y0 + rect.y, width: rect.width, height: rect.height }
}

// ---- drag ---------------------------------------------------------------------
// What a drop does: `index` is the slot among the pins the pointer is over
// (counted without the dragged app). A pinned app moves, an unpinned one with
// an entry is pinned there - unless ten are pinned - and a drop where it
// already is, or of an app without an entry, does nothing.
function dropPlan(item, index, pinIds, limit) {
    const pins = Array.prototype.slice.call(pinIds || [])
    const pin = item ? (item.pin || item.entryId || "") : ""
    if (!pin.length) return { action: "none" }
    const others = pins.filter(id => id !== pin)
    const to = Math.max(0, Math.min(others.length, Math.round(Number(index) || 0)))
    if (item.pinned) {
        const from = pins.indexOf(pin)
        return from === to ? { action: "none" } : { action: "move", id: pin, index: to }
    }
    if (pins.length >= (limit || 10)) return { action: "full" }
    return { action: "pin", id: pin, index: to }
}

// A pin's place among the defaults: @files, @terminal, @browser are the
// session's default apps (Settings > Default apps; default-apps.py's
// categories), @settings the shell's own Settings. "" for an id.
function pinCategory(pin) {
    const text = String(pin || "")
    return text === "@files" ? "files" : text === "@terminal" ? "terminal" : text === "@browser" ? "browser" : ""
}

// The desktop id a default stands for now, from default-apps.py's list
// ([{ id: "terminal", current: "Alacritty.desktop" } …]), "" when unknown.
function defaultFor(pin, categories) {
    const category = pinCategory(pin)
    if (!category.length) return ""
    const entry = Array.prototype.slice.call(categories || []).find(item => item && item.id === category)
    return entry && entry.current ? String(entry.current).replace(/\.desktop$/, "") : ""
}

// When an app that was started shows: a window more than it had, or the
// time is up. `since` is when it was started (ms), `before` its window count
// then.
function launchSettled(count, before, since, now, limit) {
    return count > before || now - since >= limit
}

// The pin slot under a point along the dock: before the first pin whose
// middle lies past it. `pins` are the pins' [start, size] along the dock,
// without the dragged one.
function slotAt(along, pins) {
    const list = Array.prototype.slice.call(pins || [])
    for (let index = 0; index < list.length; ++index)
        if (along < list[index][0] + list[index][1] / 2) return index
    return list.length
}

// ---- zones --------------------------------------------------------------------
// The zones' length together, one after the other with a gap between the
// ones that hold something.
function zonesLength(lengths, gap) {
    const used = Array.prototype.slice.call(lengths || []).filter(length => length > 0)
    return used.reduce((sum, length) => sum + length, 0) + Math.max(0, used.length - 1) * gap
}

// Where each of the three zones starts along the body. Fit: one after the
// other from the padding. Full: the start zone at the start, the end zone at
// the end, the centre zone centred but never under a neighbour.
function zoneStarts(lengths, full, bodyLength, pad, gap) {
    const l = Array.prototype.slice.call(lengths || [0, 0, 0])
    if (!full) {
        const starts = []
        let at = pad
        for (const length of l) {
            starts.push(at)
            if (length > 0) at += length + gap
        }
        return starts
    }
    const start = pad
    const end = bodyLength - pad - l[2]
    const low = l[0] > 0 ? start + l[0] + gap : start
    const high = (l[2] > 0 ? end - gap : bodyLength - pad) - l[1]
    const centred = (bodyLength - l[1]) / 2
    return [start, Math.min(Math.max(low, centred), Math.max(low, high)), end]
}
