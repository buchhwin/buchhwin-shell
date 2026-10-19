.pragma library
.import "../hypr/HyprCommands.js" as Hypr
.import "../launcher/LaunchLogic.js" as Launch

// The apps of the last session, offered again at the next login
// (Settings > Apps > Reopen after login; services/SessionAppsService.qml).
// Pure; tests/qml/SessionAppsTest.qml.
//
// When the session ends from the shell (log out, restart, shut down) the
// shell lists its windows - the desktop entry each belongs to, its window
// class, the screen and the workspace of that screen's block it is on - and
// scripts/session-apps.py adds what only Hyprland knows at that moment
// (floating, and where and how large a floating window is), then writes
// ~/.local/state/buchhwin-shell/session-apps.json, readable by the user
// alone. No title is ever kept: a window's title is a mail's subject, a
// document's name, a chat. At the next login a notification offers "Reopen";
// nothing starts by itself.
//
// Reopening starts each app through the launcher (LauncherService.launchApp:
// the wallet's path for the browsers holds) and puts every window that
// appears where its kind of window was. Browsers and VS Code bring back
// their own windows: they are started once, and the shell only places what
// they restore. A Citrix session is never started, only put back when Citrix
// has reconnected it.

var STATE_VERSION = 1
var MAX_ENTRIES = 60
// More windows than this of one app are not started again one by one (a
// terminal or a file manager opens one per start).
var MAX_LAUNCHES = 4
// At most this many starts in one reopen, whatever the file says.
var MAX_TOTAL_LAUNCHES = 20
// How long a browser gets to bring back its windows before the next entry of
// its family (a web app) is started - one started meanwhile would be a
// second window of what the browser restores itself.
var FAMILY_WAIT_MS = 20000
// Once the browser's first window is there, how long the rest of what it
// restores gets to follow (its windows come one after the other) before the
// next entry of its family is started.
var FAMILY_SETTLE_MS = 3000
// How long windows are placed after the last start.
var PLACE_MS = 90000
// The pause between two starts.
var LAUNCH_GAP_MS = 700

// VS Code and its builds restore their windows (and their folders) by
// themselves, like the browsers.
var RESTORING_IDS = /^(code|code-oss|codium|vscodium|com\.visualstudio\.code|visual-studio-code)(\.desktop)?$/i

function text(value) { return value === undefined || value === null ? "" : String(value) }
function lower(value) { return text(value).toLowerCase() }

// Hyprland's window address without the 0x and in lower case ("" for
// anything else): Quickshell's toplevels and socket2's events write it
// without, `hyprctl -j clients` with.
function normalizeAddress(value) {
    const raw = lower(value).trim().replace(/^0x/, "")
    return /^[0-9a-f]{1,16}$/.test(raw) ? raw : ""
}

// Where a window's workspace sits: the place in its monitor's block
// (`local`, 1-10) while workspaces are per monitor, else the id itself.
function workspacePlace(id, monitorName, offsets, perMonitor, block) {
    const number = Math.round(Number(id))
    const size = Math.max(1, Math.round(Number(block) || 10))
    if (perMonitor) {
        const local = number - Math.max(0, Math.round(Number((offsets || {})[monitorName]) || 0))
        if (local >= 1 && local <= size) return { workspace: local, local: true }
    }
    return { workspace: number, local: false }
}

// The shell's half of a snapshot, for scripts/session-apps.py: [{ address,
// app, cls, monitor, monitorName, workspace, local }] from the toplevels
// ([{ address, cls, app, workspace, monitor }]). Left out: special
// workspaces (the minimized, the drop-down terminal, the hidden helpers),
// windows without a class, the hidden helper classes (`hidden(cls)`).
function snapshotWindows(windows, options) {
    const settings = options || {}
    const monitors = Array.isArray(settings.monitors) ? settings.monitors : []
    const result = []
    for (const window of Array.isArray(windows) ? windows : []) {
        if (!window) continue
        const address = normalizeAddress(window.address)
        const cls = lower(window.cls).trim()
        const id = Math.round(Number(window.workspace))
        if (!address.length || !cls.length || !isFinite(id) || id < 1) continue
        if (typeof settings.hidden === "function" && settings.hidden(cls)) continue
        const monitorName = text(window.monitor)
        const monitor = monitors.find(item => item && item.name === monitorName)
        const place = workspacePlace(id, monitorName, settings.offsets, settings.perMonitor, settings.block)
        result.push({ address: "0x" + address, app: validApp(window.app) ? window.app : "", cls: cls,
                      monitor: monitor ? text(monitor.description) : "", monitorName: monitorName,
                      workspace: place.workspace, local: place.local })
        if (result.length >= MAX_ENTRIES) break
    }
    return result
}

function validApp(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 255 && !/[\u0000-\u001f\u007f]/.test(id)
}

function integer(value, low, high) {
    const number = Math.round(Number(value))
    return isFinite(number) && number >= low && number <= high ? number : null
}

// One kept window, or null. Only the fields a place needs: whatever else a
// file holds (a title, written by anything else) is not read.
function sanitizeEntry(raw) {
    if (!raw || typeof raw !== "object") return null
    const cls = lower(raw.cls).trim()
    if (!cls.length || cls.length > 255 || /[\u0000-\u001f\u007f]/.test(cls)) return null
    const workspace = integer(raw.workspace, 1, 9999)
    if (workspace === null) return null
    const entry = {
        app: validApp(raw.app) ? raw.app : "",
        cls: cls,
        monitor: typeof raw.monitor === "string" && raw.monitor.length <= 255 && !/[\u0000-\u001f]/.test(raw.monitor) ? raw.monitor : "",
        monitorName: typeof raw.monitorName === "string" && /^[A-Za-z0-9_.:@-]{1,64}$/.test(raw.monitorName) ? raw.monitorName : "",
        workspace: workspace,
        local: raw.local === true,
        floating: false
    }
    if (raw.floating === true) {
        const x = integer(raw.x, -100000, 100000), y = integer(raw.y, -100000, 100000)
        const width = integer(raw.width, 1, 100000), height = integer(raw.height, 1, 100000)
        if (x !== null && y !== null && width !== null && height !== null)
            Object.assign(entry, { floating: true, x: x, y: y, width: width, height: height })
    }
    return entry
}

function emptyState() {
    return { version: STATE_VERSION, savedAt: "", offered: false, entries: [] }
}

function parseState(source) {
    let data = null
    try { data = JSON.parse(text(source)) } catch (error) { data = null }
    const state = emptyState()
    if (!data || typeof data !== "object" || Array.isArray(data)) return state
    state.savedAt = typeof data.savedAt === "string" && data.savedAt.length <= 40 ? data.savedAt : ""
    state.offered = data.offered === true
    for (const raw of Array.isArray(data.entries) ? data.entries : []) {
        const entry = sanitizeEntry(raw)
        if (entry) state.entries.push(entry)
        if (state.entries.length >= MAX_ENTRIES) break
    }
    return state
}

// What a window is in a plan: its app, or its class for a window of no
// known app (placed when it comes back, never started).
function keyOf(app, cls) {
    return validApp(app) ? app : "class:" + lower(cls)
}

// The kept windows by app, in the order they were first seen: [{ key, app,
// cls, places }].
function groups(entries) {
    const result = []
    const byKey = {}
    for (const entry of Array.isArray(entries) ? entries : []) {
        const key = keyOf(entry.app, entry.cls)
        if (!byKey[key]) {
            byKey[key] = { key: key, app: entry.app || "", cls: entry.cls, places: [] }
            result.push(byKey[key])
        }
        byKey[key].places.push(entry)
    }
    return result
}

// "1 app" / "3 apps" kept, for the offer and the page.
function appCount(entries) {
    return groups(entries).length
}

function offerText(count) {
    const number = Math.max(0, Math.round(Number(count) || 0))
    return {
        title: "Reopen your apps?",
        body: number === 1 ? "1 app was open when your last session ended. Reopen puts it back on its screen and workspace."
            : number + " apps were open when your last session ended. Reopen puts them back on their screens and workspaces."
    }
}

// Offered once per kept session: the file says it was (`offered`), and an
// empty one has nothing to offer.
function wantsOffer(state, enabled) {
    return enabled === true && !!state && Array.isArray(state.entries) && state.entries.length > 0 && state.offered !== true
}

// ---- starting -------------------------------------------------------------------
// How an app comes back: { family, restores, placeOnly }. The browsers of
// Chromium's family are known by the program their entry runs (a web app's
// entry runs the browser - LaunchLogic.browserLauncher), so the browser and
// its web apps are one family; VS Code restores its own windows too. A Citrix
// desktop is never started by a reopen: Citrix reconnects its sessions by
// itself, and a start of the desktop's entry asks the store for a second
// session (DockLogic's Citrix notes) - its window is only put back when it
// comes. Anything else is a family of its own and opens a window per start.
function restoreKind(entry) {
    if (!entry) return { family: "", restores: false, placeOnly: false }
    const command = Array.prototype.slice.call(entry.command || [])
    const browser = command.length ? Launch.browserLauncher(command[0]) : ""
    if (browser.length) return { family: browser, restores: true, placeOnly: false }
    const citrix = Array.prototype.slice.call(entry.categories || []).some(category => lower(category) === "citrix-subscribed")
        || lower(entry.startupClass) === "wfica"
    if (citrix) return { family: "citrix", restores: true, placeOnly: true }
    return { family: text(entry.id), restores: RESTORING_IDS.test(text(entry.id)), placeOnly: false }
}

// The starts a reopen makes: [{ key, app, family, restores, count, launched }].
// `infoFor(app)` -> null for an app that is not installed (its windows are
// still placed should they come back), else { family, restores, placeOnly }.
// `openAtStart` { key: windows }: what is open already counts - an app with
// windows open is started only for the ones missing, and one that restores
// itself not at all.
function launchQueue(groupList, infoFor, openAtStart) {
    const open = openAtStart || {}
    const result = []
    let total = 0
    for (const group of Array.isArray(groupList) ? groupList : []) {
        if (!group.app) continue
        const info = typeof infoFor === "function" ? infoFor(group.app) : null
        if (!info || info.placeOnly) continue
        const already = Math.max(0, Number(open[group.key]) || 0)
        const count = info.restores ? (already > 0 ? 0 : 1)
            : Math.max(0, Math.min(group.places.length, MAX_LAUNCHES) - already)
        const allowed = Math.min(count, MAX_TOTAL_LAUNCHES - total)
        if (allowed <= 0) continue
        total += allowed
        result.push({ key: group.key, app: group.app, family: info.family || group.app, restores: info.restores === true,
                      count: allowed, launched: 0 })
    }
    return result
}

// The index of the next start, or -1. A browser's family waits while one of
// its members is starting (`familyWait` { family: until }) and no window of
// it has come; one whose app has a window by now (`openNow` { key: n }: the
// browser brought it back) is not started at all.
function nextLaunch(queue, openNow, familyWait, now) {
    const list = Array.isArray(queue) ? queue : []
    for (let index = 0; index < list.length; ++index) {
        const item = list[index]
        if (item.launched >= item.count) continue
        if (item.restores && (Number((openNow || {})[item.key]) || 0) > 0) continue
        const until = Number((familyWait || {})[item.family]) || 0
        if (until > now) continue
        return index
    }
    return -1
}

// A window of a waiting family came: the wait ends a moment later, so the
// windows the browser brings back after its first are counted as open
// before a web app of its family would be started a second time. A new map
// (`familyWait` { family: until }); the same one for a family not waiting.
function familyArrived(familyWait, family, now) {
    const waits = familyWait || {}
    const until = Number(waits[family])
    if (!text(family).length || !isFinite(until)) return waits
    const next = Object.assign({}, waits)
    next[family] = Math.min(until, Number(now) + FAMILY_SETTLE_MS)
    return next
}

// Whether anything is left to start, now or after a wait.
function launchesLeft(queue, openNow) {
    return (Array.isArray(queue) ? queue : []).some(item => item.launched < item.count
        && !(item.restores && (Number((openNow || {})[item.key]) || 0) > 0))
}

// ---- placing ---------------------------------------------------------------------
// The places still free, by key: { key: [entry, …] }.
function pendingFrom(groupList) {
    const result = {}
    for (const group of Array.isArray(groupList) ? groupList : []) result[group.key] = group.places.slice()
    return result
}

function pendingCount(pending) {
    return Object.keys(pending || {}).reduce((sum, key) => sum + ((pending[key] || []).length), 0)
}

// The first free place for a window that is one of `keys` (its app first,
// then its class) -> { key, place, pending } with the place taken, or null.
function takePlace(pending, keys) {
    for (const key of Array.isArray(keys) ? keys : []) {
        const list = (pending || {})[key]
        if (!list || !list.length) continue
        const next = Object.assign({}, pending)
        next[key] = list.slice(1)
        if (!next[key].length) delete next[key]
        return { key: key, place: list[0], pending: next }
    }
    return null
}

// Where a kept window goes now: { monitor, workspace, geometry }. Its screen
// by description, then by connector; a screen that is not here leaves the
// window on the focused one (`focusedName`), at the same place of that
// block. `screens` { name: { x, y, width, height } } (logical) put a
// floating window back at its spot on that screen, kept on it.
function targetOf(place, monitors, offsets, perMonitor, focusedName, screens) {
    if (!place) return null
    const list = (Array.isArray(monitors) ? monitors : []).filter(item => item && text(item.name).length)
    let monitor = place.monitor ? list.find(item => text(item.description) === place.monitor) : null
    if (!monitor && place.monitorName) monitor = list.find(item => item.name === place.monitorName) || null
    if (!monitor) monitor = list.find(item => item.name === focusedName) || list[0] || null
    const name = monitor ? monitor.name : ""
    const offset = perMonitor ? Math.max(0, Math.round(Number((offsets || {})[name]) || 0)) : 0
    const workspace = place.local ? offset + place.workspace : place.workspace
    let geometry = null
    const screen = (screens || {})[name]
    if (place.floating && screen && screen.width > 0 && screen.height > 0) {
        const width = Math.min(place.width, Math.round(screen.width))
        const height = Math.min(place.height, Math.round(screen.height))
        const x = Math.max(0, Math.min(place.x, Math.round(screen.width) - width))
        const y = Math.max(0, Math.min(place.y, Math.round(screen.height) - height))
        geometry = { x: Math.round(screen.x) + x, y: Math.round(screen.y) + y, width: width, height: height }
    }
    return { monitor: name, workspace: workspace, geometry: geometry }
}

// Floating, idempotent (`setfloating` / action "enable"): a window that opens
// floating by itself stays so, unlike with a toggle.
function setFloating(windowAddress) {
    const target = Hypr.address(windowAddress)
    return { legacy: "setfloating address:" + target,
             lua: "hl.dsp.window.float({ action = \"enable\", window = \"address:" + target + "\" })" }
}

function pixels(value) {
    const number = Math.round(Number(value))
    if (!isFinite(number)) throw new Error("invalid position")
    return number
}

// A floating window to an exact place and size, in the layout's logical
// pixels (what `hyprctl -j clients` reports as `at` and `size`).
function moveExact(windowAddress, x, y) {
    const target = Hypr.address(windowAddress)
    const left = pixels(x), top = pixels(y)
    return { legacy: "movewindowpixel exact " + left + " " + top + ",address:" + target,
             lua: "hl.dsp.window.move({ x = " + left + ", y = " + top + ", relative = false, window = \"address:" + target + "\" })" }
}

function resizeExact(windowAddress, width, height) {
    const target = Hypr.address(windowAddress)
    const w = pixels(width), h = pixels(height)
    if (w < 1 || h < 1) throw new Error("invalid size")
    return { legacy: "resizewindowpixel exact " + w + " " + h + ",address:" + target,
             lua: "hl.dsp.window.resize({ x = " + w + ", y = " + h + ", relative = false, window = \"address:" + target + "\" })" }
}

// The dispatchers that put one window at its place, in order: to its
// workspace without following it, then - for a floating one - floating, at
// its spot, at its size.
function placeCommands(windowAddress, target) {
    if (!target || !(target.workspace >= 1)) return []
    const address = "0x" + normalizeAddress(windowAddress)
    if (address === "0x") return []
    const steps = [Hypr.moveWindowSilent(target.workspace, address)]
    if (target.geometry) {
        steps.push(setFloating(address))
        steps.push(moveExact(address, target.geometry.x, target.geometry.y))
        steps.push(resizeExact(address, target.geometry.width, target.geometry.height))
    }
    return steps
}

// The subscribed Citrix desktop a session window's title names: the entry
// whose StartupWMClass (else its name) starts the title as a whole word -
// "LAB" is not "LABRADOR" -, the longest first; "" for none. Every session is
// a Wfica window, so the class alone cannot tell them apart (the dock's
// DockLogic.citrixEntryFor reads it the same way). `entries`: [{ id, name,
// startupClass }].
function citrixEntryFor(title, entries) {
    const source = lower(title).trim()
    if (!source.length) return ""
    let best = null
    for (const entry of Array.prototype.slice.call(entries || [])) {
        const word = lower(entry && (entry.startupClass || entry.name)).trim()
        if (!word.length || source.indexOf(word) !== 0) continue
        const next = source.charAt(word.length)
        if (next.length && /[0-9a-z_.-]/.test(next)) continue
        if (!best || word.length > best.length) best = { id: text(entry.id), length: word.length }
    }
    return best ? best.id : ""
}

// socket2's `openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE` -> { address, cls,
// title }; the title may hold commas and is only read to tell Citrix
// desktops apart, never kept.
function parseOpenWindow(data) {
    const source = text(data)
    const first = source.indexOf(",")
    const second = first < 0 ? -1 : source.indexOf(",", first + 1)
    const third = second < 0 ? -1 : source.indexOf(",", second + 1)
    if (third < 0) return null
    const address = normalizeAddress(source.slice(0, first))
    return address.length ? { address: address, cls: source.slice(second + 1, third), title: source.slice(third + 1) } : null
}
