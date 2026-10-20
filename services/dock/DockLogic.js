.pragma library
.import "../hypr/HiddenWindows.js" as Hidden
.import "MinimizeLogic.js" as Minimize
.import "../workspaces/WorkspaceLogic.js" as Workspaces

// The dock (shell/dock/Dock.qml, services/DockService.qml): pinned apps - the
// dock's own pins (LayoutService.dockLayout.pins) - and the apps that have
// windows, along one edge of a screen. Everything here is arithmetic on plain
// objects, so the tests can ask it everything the surface and the service
// decide.

var POSITIONS = ["bottom", "left", "right"]
var SPANS = ["fit", "full"]
var VISIBILITY = ["always", "intellihide", "hidden"]
var ICON_SIZES = [40, 48, 56, 64]
var MARGINS = [0, 4, 8, 16]
// What the start button opens (`dock.startOpens`): the start menu, or the
// launcher as it did before the start menu was there.
var START_OPENS = ["startMenu", "launcher"]
// Dots under an app: one per window, up to this many.
var MAX_DOTS = 3
// The smallest an icon is fitted down to when the edge runs out of room.
var MIN_ICON = 20

// Hyprland's events after which a window may have come over the dock or left
// it. There is no event for a floating window moved or resized by hand: that
// is what the slow poll is for (needsPoll). A focus change (activewindowv2)
// moves no window, and re-reading every window after each Alt+Tab bought
// nothing; nor does the focus going to another monitor (focusedmon), which
// with the focus following the mouse is every crossing of the pointer at a
// desk of three screens - each monitor keeps its workspace, and a workspace
// that changes says so itself. A workspace moved to another monitor
// (moveworkspace) takes its windows there.
var COVER_EVENTS = ["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode",
    "fullscreen", "workspace", "workspacev2", "activespecial",
    "activespecialv2", "moveworkspace", "moveworkspacev2", "pin", "togglegroup", "moveintogroup",
    "moveoutofgroup", "monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"]
// What the dock's running apps are: those of every screen on each dock, or
// on each dock those with a window on its own screen (`dock.runningOn`). The
// pins are on every dock either way.
var RUNNING_ON = ["all", "screen"]
// What a click on the app in front does (`dock.activeClick`): its next window,
// as the dock always did, or minimize it, as a Windows or KDE taskbar does -
// the Taskbar preset's.
var ACTIVE_CLICK = ["cycle", "minimize"]

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
    case "enabled": case "showRunning": case "magnification": case "badges": case "previews": case "wheelVolume":
        return text === "true" ? true : text === "false" ? false : null
    case "visibility": return VISIBILITY.indexOf(text) >= 0 ? text : null
    case "position": return POSITIONS.indexOf(text) >= 0 ? text : null
    case "span": return SPANS.indexOf(text) >= 0 ? text : null
    case "startOpens": return START_OPENS.indexOf(text) >= 0 ? text : null
    case "runningOn": return RUNNING_ON.indexOf(text) >= 0 ? text : null
    case "activeClick": return ACTIVE_CLICK.indexOf(text) >= 0 ? text : null
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
    return resolver(pins, lookup)(cls)
}

// resolve() for one list of pins, which remembers each class's answer: a
// dock's windows name few classes, over and over, and each focus change or
// window opened asked the lookup and matched every pin against every window
// again. The service keeps one for as long as its pins are the same list -
// a new list comes with every change of the pins and every scan of the
// desktop entries, which is what the lookup reads. The pins' names are
// lowered once here rather than once per window and pin; the match is
// entryMatches'.
//
// `hint`: the entry a window says it is beyond its class - a Citrix session's
// (citrixEntryFor), whose class is Wfica for every desktop. The pinned one of
// that id, else the entry itself (`byId`), else the class as usual.
function resolver(pins, lookup, byId) {
    const list = Array.prototype.slice.call(pins || []).filter(pin => pin && lower(pin.id).length > 0)
        .map(pin => ({ entry: pin, id: lower(pin.id), wm: lower(pin.startupClass), last: lower(lastSegment(pin.id)) }))
    const known = Object.create(null)
    const hinted = Object.create(null)
    const classOf = function (cls) {
        const name = String(cls || "")
        if (!name.length) return null
        if (known[name] !== undefined) return known[name]
        const low = lower(name)
        const tail = lower(lastSegment(name))
        let found = null
        for (const pin of list) {
            if (low === pin.id || (pin.wm.length > 0 && low === pin.wm) || low === pin.last || pin.id === tail) {
                found = { key: "app:" + pin.entry.id, entry: pin.entry }
                break
            }
        }
        if (!found) {
            const entry = typeof lookup === "function" ? lookup(name) : null
            found = entry && entry.id ? { key: "app:" + entry.id, entry: entry } : { key: "class:" + low, entry: null }
        }
        known[name] = found
        return found
    }
    return function (cls, hint) {
        const id = String(hint || "")
        if (!id.length || !String(cls || "").length) return classOf(cls)
        if (hinted[id] !== undefined) return hinted[id] || classOf(cls)
        const pinned = list.find(pin => pin.entry.id === id)
        const entry = pinned ? pinned.entry : typeof byId === "function" ? byId(id) : null
        hinted[id] = entry && entry.id === id ? { key: "app:" + id, entry: entry } : null
        return hinted[id] || classOf(cls)
    }
}

// ---- Citrix --------------------------------------------------------------------
// A desktop subscribed in Citrix Workspace is a desktop entry of its own
// (category Citrix-subscribed, StartupWMClass the desktop's name: RDS-Office,
// LAB), but its session is a window of class Wfica, whichever desktop it is,
// with the desktop's name at the start of its title. Matched by the class
// alone, the pin never lit up, the session showed as a second icon (Citrix
// Workspace Engine, whose StartupWMClass is Wfica) and a click on the pin
// asked the store for a second session. (Plasma's task manager also looks
// beyond the class, at the X11 instance name.)
function isCitrixEntry(categories) {
    return Array.prototype.slice.call(categories || []).some(category => lower(category) === "citrix-subscribed")
}
function isCitrixSession(cls) {
    return lower(cls) === "wfica"
}
// The id of the subscribed desktop a session window's title names: one whose
// StartupWMClass (else its name) starts the title as a whole name - "LAB" is
// not "LABRADOR", and "RDS" not "RDS-Office-2": a hyphen, a dot or an
// underscore go on with the name, as they do in RDS-Office -, the longest
// first. "" for none (the toolbar, the connection centre). `entries`: [{ id,
// name, startupClass }].
function citrixEntryFor(title, entries) {
    const text = lower(title).trim()
    if (!text.length) return ""
    let best = null
    for (const entry of Array.prototype.slice.call(entries || [])) {
        const word = lower(entry && (entry.startupClass || entry.name)).trim()
        if (!word.length || text.indexOf(word) !== 0) continue
        const next = text.charAt(word.length)
        if (next.length && /[0-9a-z_.-]/.test(next)) continue
        if (!best || word.length > best.length) best = { id: String(entry.id), length: word.length }
    }
    return best ? best.id : ""
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
// urgent, count }. `windows` are ordered by `seq` as well. Which app is in
// front is not in it (isActive): every focus change would build the apps
// anew, and every dock lay its icons out again. `options.resolve`: a
// resolver() kept between builds, else one for this build.
function build(pins, windows, lookup, options) {
    const showRunning = !options || options.showRunning !== false
    const find = options && typeof options.resolve === "function" ? options.resolve : resolver(pins, lookup)
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
        const found = find(window.appClass, window.entryHint)
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
        // `minimized`: on its special workspace (MinimizeLogic); `badge`: the
        // count its title shows, while the dock's badges are on (BadgeLogic).
        item.windows.push({ address: window.address, workspace: window.workspace,
                            workspaceName: String(window.workspaceName || ""), monitor: window.monitor,
                            seq: window.seq || 0, urgent: window.urgent === true, appClass: String(window.appClass),
                            minimized: Minimize.isParked(window.workspaceName), badge: Math.max(0, Number(window.badge) || 0) })
    }
    for (const item of items) {
        item.running = item.windows.length > 0
        item.urgent = item.windows.some(window => window.urgent)
        item.count = item.windows.length
        item.minimized = item.windows.filter(window => window.minimized).length
    }
    return items
}

// The windows a dock on `monitor` shows when its running apps are its own
// screen's (RUNNING_ON "screen"): the pins stay, with the windows they have
// there.
function windowsOn(windows, monitor) {
    return Array.prototype.slice.call(windows || []).filter(window => window && window.monitor === monitor)
}

// Whether an app is the one in front: one of its windows has the focus
// (DockService.activeAddress, "" for none).
function isActive(item, activeAddress) {
    const address = String(activeAddress || "")
    return !!item && address.length > 0 && Array.prototype.slice.call(item.windows || []).some(window => window && window.address === address)
}

// Whether a list KeyedLogic.keep handed back is the previous one entry for
// entry, every object the very one it was. The list itself is then handed
// out again: a binding that returns the same object notifies nobody, where
// an equal new list re-ran every dock's layout - several times for each
// workspace switch, and for every panel opened and closed.
function sameObjects(previous, next) {
    const a = previous || [], b = next || []
    if (a.length !== b.length) return false
    for (let index = 0; index < a.length; ++index)
        if (a[index] !== b[index]) return false
    return true
}

// The focused window's address while it is the one in front: on the focused
// workspace, on a special one (open over it), pinned to all of them, or with
// nothing known to say otherwise; else "". Quickshell keeps the last window
// as Hyprland's `activeToplevel` when an empty workspace takes the focus.
// window: { address, workspace, pinned, parked (minimized) }.
function frontAddress(window, focusedId) {
    if (!window || !window.address) return ""
    // Minimized: Quickshell keeps it as the active window when it was the
    // last one on its workspace, and it is on a special workspace - which
    // otherwise counts as open over the focused one.
    if (window.parked === true) return ""
    const workspace = Number(window.workspace)
    const focused = Number(focusedId)
    if (!(focused > 0) || !(workspace > 0) || window.pinned === true) return String(window.address)
    return workspace === focused ? String(window.address) : ""
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

// clickTarget with minimized windows: a window it would bring to the front
// that is minimized comes back instead ("restore": focusing it would open its
// special workspace over the screen), and with `activeClick` "minimize" (the
// Taskbar preset's, dock.activeClick) a click on the app in front minimizes
// its window, as a Windows or KDE taskbar does - the next click brings it
// back, since the window used last is the one restored. A window that cannot
// be minimized (MinimizeLogic.canMinimize: the drop-down terminal, a
// scratchpad) cycles as before.
function clickPlan(item, activeAddress, mru, activeClick) {
    const target = clickTarget(item, activeAddress, mru)
    const windows = (item && item.windows) || []
    const active = windows.find(window => window.address === activeAddress) || null
    if (active && activeClick === "minimize" && Minimize.canMinimize(active)) return { action: "minimize", address: active.address }
    if (target.action !== "focus") return target
    const window = windows.find(candidate => candidate.address === target.address)
    return window && window.minimized === true ? { action: "restore", address: target.address } : target
}

// The marks under an app, one per window up to `max`: "window", "minimized"
// (drawn hollow) - or one "active" bar for the app in front, one "launching"
// (faint) for an app started and not running yet, one "window" for one that
// runs without windows of its own (the shell's Settings). In the windows'
// order.
function dotStates(item, running, active, launching, max) {
    const windows = Array.prototype.slice.call((item && item.windows) || [])
    if (!running) return launching ? ["launching"] : []
    if (active) return ["active"]
    if (!windows.length) return ["window"]
    const limit = Math.max(1, Math.round(Number(max) || MAX_DOTS))
    return windows.slice(0, limit).map(window => window && window.minimized === true ? "minimized" : "window")
}

// The desktop action that opens a new window, when the entry has one (Brave,
// Chrome: "new-window"; VS Code: "new-empty-window"; never the private one),
// else "". A bare "New" counts only when it runs the entry's own program
// (Alacritty's "New Terminal"): elsewhere it may well be a new document.
// `command` is the entry's (DesktopEntry.command).
function program(command) {
    const list = Array.prototype.slice.call(command || [])
    const first = String(list.length ? list[0] : "")
    return first.split("/").pop()
}
function newWindowAction(actions, command) {
    const list = Array.prototype.slice.call(actions || [])
    const own = program(command)
    const found = list.find(action => {
        const id = String(action && action.id || "")
        if (/^(new[-_ ]?(empty[-_ ]?)?window|new[-_ ]?instance)$/i.test(id)) return true
        return /^new$/i.test(id) && own.length > 0 && program(action.command) === own
    })
    return found ? found.id : ""
}

// The rows of an app's menu, top to bottom. Kinds: window (one per window, up
// to `maxWindows`, then a "more"), new, action (desktop actions but the new
// window one), pin/unpin, close. A pin row that is off says why (`reason`:
// "full", or "hidden" for an entry the dock could not draw once pinned).
// `command` is the entry's own, for the new window action. With `options`
// { minimize: true } (the dock's menu) a minimized window's row says so
// (`minimized`), and after the windows come minimize (the ones that can be,
// MinimizeLogic.canMinimize) and restore (the ones that are), each with its
// count.
function menuRows(item, actions, pinnedFull, maxWindows, command, options) {
    if (!item) return []
    const rows = []
    const windows = item.windows || []
    const minimizing = !!options && options.minimize === true
    const shown = Math.max(0, Math.min(windows.length, maxWindows === undefined ? windows.length : maxWindows))
    for (let index = 0; index < shown; ++index) {
        const row = { kind: "window", address: windows[index].address, workspace: windows[index].workspace,
                      workspaceName: String(windows[index].workspaceName || ""), monitor: String(windows[index].monitor || "") }
        if (minimizing && windows[index].minimized === true) row.minimized = true
        rows.push(row)
    }
    if (windows.length > shown) rows.push({ kind: "more", count: windows.length - shown })
    if (minimizing) {
        const parked = windows.filter(window => window && window.minimized === true).length
        const free = windows.filter(window => window && window.minimized !== true && Minimize.canMinimize(window)).length
        if (free > 0) rows.push({ kind: "minimize", count: free })
        if (parked > 0) rows.push({ kind: "restore", count: parked })
    }
    // The shell's Settings and a default's placeholder: no entry of their
    // own to start a second time or to list actions of.
    if (item.special) {
        rows.push({ kind: "unpin" })
        return rows
    }
    if (item.entryId) {
        rows.push({ kind: "new" })
        const skip = newWindowAction(actions, command)
        for (const action of Array.prototype.slice.call(actions || []))
            if (action && action.id !== skip) rows.push({ kind: "action", id: action.id, name: action.name || action.id })
        if (item.pinned) rows.push({ kind: "unpin" })
        else if (item.pinnable === false) rows.push({ kind: "pin", enabled: false, reason: "hidden" })
        else rows.push(pinnedFull ? { kind: "pin", enabled: false, reason: "full" } : { kind: "pin", enabled: true })
    }
    if (windows.length) rows.push({ kind: "close", count: windows.length })
    return rows
}

// Where a window is, for its row in the menu: "Workspace 3" in the number its
// pip shows (WorkspaceLogic.title: `monitor` the window's, `order` the
// monitors in their blocks' order, empty without blocks), a named workspace
// by its name, a special one (Hyprland's scratchpads, which have negative
// ids) by its name without "special:" - the unnamed one is "Scratchpad" -,
// and nothing for a workspace not known.
function workspaceLabel(id, name, monitor, order) {
    const text = String(name || "")
    // A minimized window's own special workspace (MinimizeLogic).
    if (Minimize.isParked(text)) return Minimize.parkedLabel(text, order)
    if (text === "special" || text.indexOf("special:") === 0) {
        const rest = text.slice("special:".length)
        return rest.length && rest !== "special" ? "Scratchpad " + rest : "Scratchpad"
    }
    return Workspaces.title(id, text, monitor, order)
}

// ---- panels out of the dock -------------------------------------------------------
// Where a panel opened from a place on the dock stands (`rect`, on the
// screen): above it on a bottom dock, beside it on a side one, centred on it
// along the edge. A pill's click, an app's menu and the start menu opened
// without a click all come out of the dock this way. `gap` is measured from
// the dock's `body` (its drawn base, on the screen) when it is given - an
// item sits inside the body, and a gap measured from the item was used up
// inside a taskbar, which left the start menu flush on it - else from the
// item itself.
function panelAnchor(edge, rect, gap, body) {
    if (!validRect(rect)) return {}
    const space = Math.max(0, Number(gap) || 0)
    const base = validRect(body) ? body : rect
    if (edge === "left")
        return { anchorY: Math.round(rect.y + rect.height / 2), anchorLeft: base.x + base.width + space, fromDock: true }
    if (edge === "right")
        return { anchorY: Math.round(rect.y + rect.height / 2), anchorRight: base.x - space, fromDock: true }
    return { anchorX: Math.round(rect.x + rect.width / 2), anchorBottom: base.y - space, fromDock: true }
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

// A window's place (global, logical) from Hyprland's record: `at` and `size`,
// which refreshToplevels() fills. Whether it has one at all, and the rect -
// null for none or an empty one.
function hasPlace(window) {
    return !!window && !!window.at && !!window.size && window.at.length >= 2 && window.size.length >= 2
}
function windowRect(window) {
    if (!hasPlace(window)) return null
    const rect = { x: Number(window.at[0]), y: Number(window.at[1]), width: Number(window.size[0]), height: Number(window.size[1]) }
    return validRect(rect) ? rect : null
}

// Intellihide: a window touches the dock's body (global coordinates, the dock
// as shown, plus `slack`). A window without a geometry yet does not count -
// unknown is not covered, as for fullscreen (FullscreenLogic).
function covered(body, windows, view, slack) {
    if (!validRect(body)) return false
    for (const window of windows || []) {
        if (!onView(window, view)) continue
        const rect = windowRect(window)
        if (rect && overlaps(rect, body, slack)) return true
    }
    return false
}

// Floating windows move without telling anyone, so while one could come over
// a dock or leave it the service asks again every so often: the one with the
// focus (a window moved by hand or by keys has it), one that touches the
// dock already (to see it go) and one whose place is not known yet. Only on
// a dock that is drawn - `bodies` holds a body per monitor, and none under a
// fullscreen window, where a floating player or game would have been read
// once a second for as long as it played -, and never for a floating window
// elsewhere: a picture-in-picture pinned to every workspace, a dialog at the
// top of the screen. `active`: the focused window's address; `slack` as for
// covered().
function needsPoll(windows, views, bodies, active, slack) {
    const focused = String(active || "")
    for (const view of views || []) {
        const body = view ? (bodies || {})[view.monitor] : null
        if (!validRect(body)) continue
        for (const window of windows || []) {
            if (!window || window.floating !== true || !onView(window, view)) continue
            if (focused.length && window.address === focused) return true
            if (!hasPlace(window)) return true
            const rect = windowRect(window)
            if (rect && overlaps(rect, body, slack)) return true
        }
    }
    return false
}

// The special workspace open on each monitor, from `hyprctl -j monitors`
// (`specialWorkspace.name`, "" for none). Hyprland tells of one only as it
// opens or closes (activespecial), so one that was open before the dock
// listened - at the start, or opened while the dock was off - is read once
// this way; Quickshell's own monitors carry no record of it.
function specialsFrom(monitors) {
    const result = {}
    for (const monitor of Array.prototype.slice.call(monitors || []))
        if (monitor && monitor.name)
            result[String(monitor.name)] = String(monitor.specialWorkspace && monitor.specialWorkspace.name || "")
    return result
}
// That read laid over what the events said: a monitor whose activespecial
// came after the read was asked for (`fresh`: { name: true }) keeps the
// event's word, which is newer.
function seededSpecials(current, read, fresh) {
    const next = Object.assign({}, current || {})
    for (const name of Object.keys(read || {}))
        if (!(fresh || {})[name]) next[name] = read[name]
    return next
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
    // A drag on it keeps the whole surface: a pointer that left the body
    // would be a leave, and Qt cancels the drag at a leave.
    if (s.dragging) return "window"
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

// What Super+Shift+D does (DockService.toggleFromKey). `s`: { enabled, target
// (the screen it acts on), fullscreen (a fullscreen window there), hotkey
// (the screen the key showed the dock on), peeking (that was only the look
// after "on") }. "on": the dock is switched on and shown for a moment;
// "fullscreen": nothing - the dock is not drawn under a fullscreen window,
// and keys armed then took the keyboard the moment the fullscreen ended;
// "hidden": the key's dock goes again; "shown": shown with the keyboard.
function keyAction(state) {
    const s = state || {}
    if (!s.enabled) return "on"
    if (!String(s.target || "").length) return "none"
    if (s.fullscreen) return "fullscreen"
    if (s.hotkey === s.target && !s.peeking) return "hidden"
    return "shown"
}

// The dock had the keyboard and a panel changed (`active`, "" for none):
// whether the dock keeps the keys, and whether its menu holds them for it
// meanwhile. The dock's menu takes the keys with a grab of its own, and the
// dock's grab steps aside for it - the compositor ends the older grab when a
// newer one starts, which used to end the dock's keyboard mode. Closed with
// Escape, the keys come back to the dock; closed by a click elsewhere, an
// action or another panel, the dock lets them go.
function keysAfterPanel(active, withMenu, escaped) {
    const panel = String(active || "")
    if (panel === "dockMenu") return { keep: true, withMenu: true }
    if (!panel.length && withMenu) return { keep: escaped === true, withMenu: false }
    return { keep: !panel.length, withMenu: false }
}

// Where the keys can go on the dock: its apps (0 .. count - 1) and the items
// beside them that open something - the start button, and on a taskbar its
// status, notifications and clock -: the ones before the apps at -1, -2 ...
// (-1 the nearest), the ones after them at count, count + 1 ... `before` and
// `after` are how many there are of each.
function keyRange(count, before, after) {
    const n = Math.max(0, Math.round(count || 0))
    const b = Math.max(0, Math.round(before || 0))
    const a = Math.max(0, Math.round(after || 0))
    if (n + a > 0) return { low: -b, high: n + a - 1 }
    return { low: -b, high: b > 0 ? -1 : 0 }
}
// What is at a place of the keys: { kind: "app", index }, { kind: "item",
// type }, or null for nothing. `before` and `after` are the items' types,
// each list in order along the dock (keySides).
function keyStop(index, count, before, after) {
    const n = Math.max(0, Math.round(count || 0))
    const b = Array.prototype.slice.call(before || [])
    const a = Array.prototype.slice.call(after || [])
    const at = Math.round(Number(index) || 0)
    if (at < 0) return at >= -b.length ? { kind: "item", type: b[b.length + at] } : null
    if (at < n) return { kind: "app", index: at }
    return at - n < a.length ? { kind: "item", type: a[at - n] } : null
}
// The items beside the apps that the keys reach, before and after them
// along the dock. `items`: [{ type, rect }], where the dock's pills reported
// them (LayoutService.dockItemRect - only a shown item has a place); `apps`:
// the apps' place (null: no apps here, everything is before them); `opens`:
// whether a click on a type opens something. The apps themselves are not
// one of them.
function keySides(items, apps, vertical, opens) {
    const along = rect => vertical ? rect.y : rect.x
    const list = Array.prototype.slice.call(items || [])
        .filter(item => item && item.type !== "apps" && validRect(item.rect) && (typeof opens !== "function" || opens(item.type)))
        .sort((a, b) => along(a.rect) - along(b.rect))
    const split = validRect(apps) ? along(apps) : Infinity
    return { before: list.filter(item => along(item.rect) < split).map(item => item.type),
             after: list.filter(item => along(item.rect) >= split).map(item => item.type) }
}
// Every type of item on a dock layout (LayoutService.dockLayout), once each.
function layoutTypes(layout) {
    const types = []
    for (const zone of ["left", "center", "right"])
        for (const pill of (layout && layout[zone]) || [])
            for (const item of (pill && pill.items) || [])
                if (item && item.type && types.indexOf(item.type) < 0) types.push(item.type)
    return types
}

// ---- geometry ------------------------------------------------------------------
function vertical(edge) { return edge === "left" || edge === "right" }

// The room an "always" dock reserves: its body and its margin on each side,
// less the gap Hyprland puts between a window and a reserved area anyway -
// its `gaps_out`, the mode's "Gap to screen edge" in Settings > Appearance,
// not a fixed 12: with the laptop mode's 8 every window's bottom ran 4 px
// under a taskbar. The windows then end the margin away from the body
// whatever the gap; a gap wider than all of it leaves them further off,
// as a zone cannot be less than nothing.
function reserveZone(margin, across, gapsOut) {
    const m = Math.max(0, Number(margin) || 0)
    const a = Math.max(0, Number(across) || 0)
    const g = Math.max(0, Number(gapsOut) || 0)
    return Math.max(0, m * 2 + a - g)
}

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

// The room the apps have along the body: the body at its longest (`room`,
// the edge less the margins) less its padding, every other zone, the gaps
// between the zones that hold something, and whatever else shares a zone
// with the apps. `zones`: [{ apps, length (a zone without the apps), beside
// (in the apps' zone: the rest of that zone) }]. -1 when no zone holds them.
// Measured without the apps themselves, which are fitted into it.
function appsRoom(room, pad, gap, zones) {
    const list = Array.prototype.slice.call(zones || [])
    const at = list.findIndex(zone => zone && zone.apps === true)
    if (at < 0) return -1
    let used = 0
    let taken = 0
    list.forEach((zone, index) => {
        const length = index === at ? Math.max(0, Number(zone.beside) || 0) : Math.max(0, Number(zone && zone.length) || 0)
        if (index === at || length > 0) used += 1
        taken += length
    })
    return Math.max(0, room - 2 * pad - taken - Math.max(0, used - 1) * gap)
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
// What a drop does: `index` is the place among the stored pins (counted
// without the dragged app; storedSlot). A pinned app moves, an unpinned one
// with an entry is pinned there - unless the pins are full (`limit`) - and a
// drop where it already is, or of an app without an entry, does nothing.
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
    if (pins.length >= limit) return { action: "full" }
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

// A default's pin that names no app the dock can draw: the session's list
// not read yet, none set, or a hidden helper set (a NoDisplay entry). It keeps
// its place with the category's glyph instead of leaving the dock; once the
// list is `known`, it asks for an app ("choose": a click opens Settings >
// Default apps), before that ("default") a click starts the default the way
// its hotkey does. Either way it is `special`: no entry of its own, so its
// menu offers no New window that would start nothing. `glyphs`: { files,
// terminal, browser }.
var DEFAULT_NAMES = { files: "File manager", terminal: "Terminal", browser: "Web browser" }
var DEFAULT_CHOICES = { files: "Choose a file manager", terminal: "Choose a terminal", browser: "Choose a web browser" }
function defaultPlaceholder(pin, known, glyphs) {
    const category = pinCategory(pin)
    if (!category.length) return null
    return { id: "default:" + category, name: known ? DEFAULT_CHOICES[category] : DEFAULT_NAMES[category],
             icon: "", startupClass: "", pin: pin, special: known ? "choose" : "default",
             glyph: String((glyphs || {})[category] || "") }
}

// When an app that was started shows: a window more than it had, or the
// time is up. `since` is when it was started (ms), `before` its window count
// then.
function launchSettled(count, before, since, now, limit) {
    return count > before || now - since >= limit
}

// The same for a start the dock watches (DockService.markLaunching):
// `state` as it was at the click { since, before (its window count), active
// (it was in front) }, `item` as it is now { count, active }. Done at a
// window more than it had and at the limit - and sooner where no new window
// may ever come: a single-instance app started again (Spotify, Discord,
// Steam) only raises its window, which brings it to the front, and an app
// that had windows already (New window, a middle click) is given a share of
// the limit (RELAUNCH_SHARE) - its icon breathed for the whole ten seconds.
var RELAUNCH_SHARE = 0.25
function launchDeadline(state, limit) {
    const s = state || {}
    return (Number(s.since) || 0) + (Number(s.before) > 0 ? limit * RELAUNCH_SHARE : limit)
}
function launchDone(state, item, now, limit) {
    const s = state || {}
    const it = item || {}
    if (launchSettled(Number(it.count) || 0, Number(s.before) || 0, Number(s.since) || 0, now, limit)) return true
    if (it.active === true && s.active !== true) return true
    return now >= launchDeadline(s, limit)
}
// How long until the first of the starts in `states` ({ key: state }) is
// due: the one timer the service keeps for them, -1 for none.
function launchWait(states, now, limit) {
    let wait = -1
    for (const key of Object.keys(states || {})) {
        const left = Math.max(0, launchDeadline(states[key], limit) - now)
        if (wait < 0 || left < wait) wait = left
    }
    return wait
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

// The slot a drop lands in, counted over the pins the dock shows, as a place
// in the stored list - which also holds pins the dock cannot draw (an app
// that is gone): before the shown pin at that slot, or at the end. Both
// without the dragged pin.
function storedSlot(slot, shownPins, storedPins, dragged) {
    const shown = Array.prototype.slice.call(shownPins || []).filter(pin => pin !== dragged)
    const others = Array.prototype.slice.call(storedPins || []).filter(pin => pin !== dragged)
    const index = Math.max(0, Math.round(Number(slot) || 0))
    if (index >= shown.length) return others.length
    const at = others.indexOf(shown[index])
    return at >= 0 ? at : others.length
}

// What letting go of a dragged app does: a drop among the pins (`dropSlot`
// >= 0, the pointer still near the dock), an unpin for a pinned app pulled
// `reach` slots and more away from the dock, else nothing. `away` is how far
// the pointer left the dock across it; one not known (Infinity) does
// nothing. A drag the system took away is cancelOutcome's.
// Whether a press has become a drag: moved `along` the dock past the
// threshold, or pulled `out` past the icon by it - straight up off a bottom
// dock is how a pin is pulled off, and counted along alone that never began
// a drag. Out counts only beyond the icon, so a click that wobbles on it
// stays a click.
function dragStarts(along, out, threshold) {
    return Math.abs(Number(along) || 0) >= threshold || Math.max(0, Number(out) || 0) >= threshold
}
// `room`: how far the pointer can go off the body and still be on the dock's
// surface (its headroom above a bottom dock, 36 px at the defaults). A pull
// that leaves the surface is a pointer leave, and Qt cancels the drag there -
// so the unpin distance is never more than that room, or it could not be
// reached (16.10., nested: a straight pull off the taskbar never unpinned).
function unpinDistance(slot, reach, room) {
    const far = Math.max(0, Number(slot) || 0) * Math.max(0, Number(reach) || 0)
    const near = Number(room)
    return isFinite(near) && near > 0 ? Math.min(far, near) : far
}
function dragAway(item, away, slot, reach, room) {
    const out = Number(away)
    return !!item && item.pinned === true && isFinite(out) && out >= unpinDistance(slot, reach, room)
}
function dragOutcome(item, away, slot, dropSlot, reach, room) {
    if (!item || !isFinite(Number(away))) return "none"
    if (dragAway(item, away, slot, reach, room)) return "unpin"
    return dropSlot >= 0 && Math.max(0, Number(away) || 0) < slot ? "drop" : "none"
}
// A drag the system took away. A pull off the dock ends that way too: the
// surface is all the input the dock has, and the pointer leaving it is a
// leave, at which Qt cancels the press - the pin stayed when it was pulled
// further than the surface reaches, the natural, decisive way to pull it
// off. So a cancel unpins when the pull had reached the unpin distance (the
// label said "Unpin"), or was still going away past half of it: a quick
// pull can leave the surface between two moves without ever reporting the
// last stretch. `away` is the last distance reported, `rising` whether it
// was growing then. Anything else does nothing (one undo step either way).
function cancelOutcome(item, away, rising, slot, reach, room) {
    const out = Number(away)
    if (!item || item.pinned !== true || !isFinite(out)) return "none"
    if (dragAway(item, out, slot, reach, room)) return "unpin"
    return rising === true && out >= unpinDistance(slot, reach, room) / 2 ? "unpin" : "none"
}

// A drag whose app went meanwhile (its last window closed, its pin taken
// away elsewhere, the dock gone): its icon - and with it the end of the drag -
// is gone, which kept the dock shown for good with its whole surface taking
// clicks meant for the windows below.
function dragLost(key, items) {
    const k = String(key || "")
    return k.length > 0 && !Array.prototype.slice.call(items || []).some(item => item && item.key === k)
}

// ---- the names over the icons -------------------------------------------------------
// The name as the pointer goes over the icons. `state`: { index, shown } now;
// `index`: the icon entered or left, `entered` which. The next { index,
// shown }, and what the two timers do: "show" (the delay starts, the name
// shows when it ends), "hide" (a short grace starts, the name goes when it
// ends), "stop" (both stop), "keep" (both as they are). Once a name is up the
// next icon's shows at once: the pointer crosses the gap between two icons,
// where no icon has it, within the grace. A leave of an icon the name has
// already left (the next one's enter came first) changes nothing.
function labelAfter(state, index, entered) {
    const s = state || {}
    const at = Math.round(Number(index))
    const shown = s.shown === true
    const current = s.index === undefined || s.index === null ? -1 : s.index
    if (!entered) {
        if (at !== current) return { index: current, shown: shown, timer: "keep" }
        return { index: current, shown: shown, timer: shown ? "hide" : "stop" }
    }
    return shown ? { index: at, shown: true, timer: "stop" } : { index: at, shown: false, timer: "show" }
}

// The name once the row has `count` icons: an icon taken away under the
// pointer while it was the last one (its app closed) is gone without a
// leave - a delegate that goes says nothing as it goes - and its name stayed
// up past the row's end, an empty bubble where no icon is. Taken down, both
// timers stopped; any other row keeps the name where it is.
function labelInRow(state, count) {
    const s = state || {}
    const index = s.index === undefined || s.index === null ? -1 : s.index
    return index < Math.max(0, Math.round(Number(count) || 0)) ? null : { index: -1, shown: false, timer: "stop" }
}

// ---- zones --------------------------------------------------------------------
// The pills of a zone that show something, counted by their own condition
// (`hasContent`), never by `visible`: a hidden dock hides its content, every
// pill under it then reads invisible (testing.md pitfall 89), and a zone that
// counted those shrank the hidden dock's body - its reveal strip and its
// intellihide rect - to its padding.
function shownFlags(pills) {
    return Array.prototype.slice.call(pills || []).map(pill => pill !== null && pill !== undefined && pill.hasContent === true)
}
function shownCount(pills) {
    return shownFlags(pills).filter(Boolean).length
}

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
