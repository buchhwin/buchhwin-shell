.pragma library
.import "../workspaces/WorkspaceLogic.js" as Workspaces
.import "../hypr/HiddenWindows.js" as Hidden

// Pure helpers for the window overview: workspaces with their windows placed
// relative to the monitor, from `hyprctl -j clients / monitors / workspaces`.

function logicalMonitor(monitor) {
    const rotated = Number(monitor.transform) % 2 === 1
    const scale = Number(monitor.scale) || 1
    return {
        id: monitor.id, name: String(monitor.name), x: Number(monitor.x) || 0, y: Number(monitor.y) || 0,
        width: Math.round((rotated ? monitor.height : monitor.width) / scale),
        height: Math.round((rotated ? monitor.width : monitor.height) / scale),
        focused: monitor.focused === true,
        activeWorkspace: monitor.activeWorkspace ? Number(monitor.activeWorkspace.id) : -1
    }
}

function clamp01(value) {
    return Math.max(0, Math.min(1, value))
}

// Workspaces (regular ids > 0) sorted by id, each with windows in stacking
// order (least recently focused first so the latest is drawn on top).
// `mode` and `count` are the workspace setting, and the overview obeys all of
// it, not one value of it: `fixed` shows 1..count the way the indicator does,
// `gapless` fills the empty ones between the occupied back in, `open` shows
// what exists.
//
// The first go at this only taught it `gapless`, which is the mode nobody was
// on. The pill and the overview showing different workspaces is worse than
// either choice alone - it was exactly the complaint: workspace 2 dimmed in
// the pill and simply absent from Super+W.
function build(clients, monitors, workspaces, mode, count, perMonitor) {
    const screens = (monitors || []).map(logicalMonitor)
    const byId = {}
    const ensure = (id, name, monitorId) => {
        if (!byId[id]) {
            const screen = screens.find(item => item.id === monitorId) || screens[0] || { name: "", x: 0, y: 0, width: 1920, height: 1080, activeWorkspace: -1 }
            byId[id] = { id: id, name: String(name || id), monitor: screen.name, active: screen.activeWorkspace === id,
                         aspect: screen.height / Math.max(1, screen.width), windows: [], screen: screen }
        }
        return byId[id]
    }
    for (const workspace of workspaces || [])
        if (Number(workspace.id) > 0) ensure(Number(workspace.id), workspace.name, workspace.monitorID)
    // Before the windows, so a filled-in workspace is an ordinary entry that a
    // window could still land on rather than a special case.
    //
    // A workspace that does not exist has no monitor to belong to, so the
    // filled-in ones go to the focused one. There is nothing better to know:
    // Hyprland gives a workspace its monitor when it is created, and these are
    // the ones that have not been.
    if (perMonitor) {
        // Each monitor's own block gets filled in separately, on that monitor.
        // Filling globally would put every monitor's missing numbers on the
        // focused one and the grouping below would be a lie.
        const order = Workspaces.monitorOrder(screens)
        for (let index = 0; index < order.length; ++index) {
            const screen = screens.find(item => item.name === order[index])
            const base = index * Workspaces.perMonitorBlock
            const mine = Object.keys(byId).map(id => byId[id])
                .filter(entry => entry.monitor === order[index])
                .map(entry => Workspaces.localId(entry.id))
            for (const local of wantedIds(mine, mode, count))
                if (!byId[base + local]) ensure(base + local, String(base + local), screen ? screen.id : undefined)
        }
    } else {
        const wanted = wantedIds(Object.keys(byId).map(id => byId[id].id), mode, count)
        if (wanted.length) {
            const home = screens.find(item => item.focused) || screens[0]
            for (const id of wanted)
                if (!byId[id]) ensure(id, String(id), home ? home.id : undefined)
        }
    }
    for (const client of clients || []) {
        if (!client || !client.workspace || Number(client.workspace.id) <= 0 || client.mapped === false || client.hidden === true
            || Hidden.isHiddenClient(client)) continue
        const entry = ensure(Number(client.workspace.id), client.workspace.name, client.monitor)
        const screen = entry.screen
        const at = Array.isArray(client.at) ? client.at : [0, 0]
        const size = Array.isArray(client.size) ? client.size : [0, 0]
        const x = clamp01((at[0] - screen.x) / Math.max(1, screen.width))
        const y = clamp01((at[1] - screen.y) / Math.max(1, screen.height))
        entry.windows.push({
            address: String(client.address), title: String(client.title || ""), appClass: String(client.class || ""),
            x: x, y: y,
            width: Math.max(0.02, Math.min(1 - x, size[0] / Math.max(1, screen.width))),
            height: Math.max(0.02, Math.min(1 - y, size[1] / Math.max(1, screen.height))),
            floating: client.floating === true, fullscreen: Number(client.fullscreen) > 0,
            focusOrder: Number(client.focusHistoryID) >= 0 ? Number(client.focusHistoryID) : 999
        })
    }
    const order = perMonitor ? Workspaces.monitorOrder(screens) : []
    return Object.keys(byId).map(Number).sort((a, b) => a - b).map(id => {
        const entry = byId[id]
        entry.windows.sort((a, b) => b.focusOrder - a.focusOrder)
        delete entry.screen
        // What the card is called. With blocks that is the monitor's own
        // number, unless the workspace has a name somebody chose, or unless it
        // is sitting on a monitor whose block it does not belong to - then the
        // real number, because two cards called "1" in one overview is worse
        // than a number that looks odd.
        const named = entry.name !== String(id)
        const home = order.indexOf(entry.monitor)
        const mine = perMonitor && home >= 0 && Workspaces.monitorIndexOf(id) === home
        entry.label = named ? entry.name : String(mine ? Workspaces.localId(id) : id)
        return entry
    })
}

// The overview, gathered by monitor: one row per screen, in the order the
// Displays page numbers them, with the screen the overview opened on first
// because that is where you look. One flow of every workspace of every monitor
// is unreadable the moment there is more than one screen - and with blocks it
// can be twenty-seven cards.
function groups(entries, monitors) {
    const screens = (monitors || []).map(logicalMonitor)
    const order = Workspaces.monitorOrder(screens)
    const focusedName = (screens.find(item => item.focused) || {}).name || ""
    const list = (entries || [])
    const result = []
    for (let index = 0; index < order.length; ++index) {
        const screen = screens.find(item => item.name === order[index])
        result.push({
            monitor: order[index],
            number: index + 1,
            focused: order[index] === focusedName,
            // Where this monitor's block of numbers starts, so the row's
            // "New workspace" card offers the next free one *of this monitor*.
            base: index * Workspaces.perMonitorBlock,
            // Each row's cards get their own screen's shape: a portrait
            // monitor beside two landscape ones is exactly the case this is
            // for, and one aspect for all three would draw the windows wrong.
            aspect: screen ? screen.height / Math.max(1, screen.width) : 0.5625,
            workspaces: list.filter(entry => entry.monitor === order[index])
        })
    }
    // A workspace on a monitor the list does not know keeps a row of its own
    // rather than vanishing from the overview entirely. Last, because it is
    // the one nobody is looking for.
    const orphans = list.filter(entry => order.indexOf(entry.monitor) < 0)
    if (orphans.length)
        result.push({ monitor: "", number: 0, focused: false, base: 0, aspect: 0.5625, workspaces: orphans })
    // The focused row moves to the front by hand rather than by sorting: a
    // sort with a two-valued comparator is only stable if the engine says so,
    // and this one is not - it put the homeless row in the middle and a real
    // monitor at the end.
    const at = result.findIndex(row => row.focused)
    if (at > 0) result.unshift(result.splice(at, 1)[0])
    return result
}

function matches(window, query) {
    const q = String(query || "").trim().toLowerCase()
    return !q.length || window.title.toLowerCase().includes(q) || window.appClass.toLowerCase().includes(q)
}

// Windows in reading order (workspace, then left-to-right, top-to-bottom)
// for keyboard navigation.
function flatWindows(workspaces, query) {
    const result = []
    for (const workspace of workspaces)
        workspace.windows.filter(window => matches(window, query))
            .slice().sort((a, b) => a.y - b.y || a.x - b.x)
            .forEach(window => result.push(Object.assign({ workspace: workspace.id }, window)))
    return result
}

// Which workspace numbers the overview should show, from the ids that exist
// and the setting. The same three answers the indicator gives, so the two
// cannot disagree - which is the only reason this is not written twice.
function wantedIds(existing, mode, count) {
    const have = (existing || []).filter(id => typeof id === "number" && id > 0)
    switch (Workspaces.normalizeMode(mode)) {
    case "fixed": {
        const limit = Workspaces.normalizeCount(count)
        const ids = []
        for (let id = 1; id <= limit; ++id) ids.push(id)
        return ids
    }
    case "gapless":
        return Workspaces.spanIds(have)
    default:
        return []
    }
}

function nextFreeWorkspace(workspaces) {
    const ids = workspaces.map(workspace => workspace.id)
    let id = 1
    while (ids.indexOf(id) >= 0) id += 1
    return id
}

// The next free number inside one monitor's block, for that row's "New
// workspace" card. A global next-free would hand the third monitor the number
// 2, which belongs to the first.
function nextFreeIn(workspaces, base) {
    const start = Math.max(0, Math.round(Number(base)) || 0)
    const ids = (workspaces || []).map(workspace => workspace.id)
    for (let local = 1; local <= Workspaces.perMonitorBlock; ++local)
        if (ids.indexOf(start + local) < 0) return start + local
    return start + 1
}

function normalizeAddress(address) {
    const text = String(address || "").toLowerCase()
    return text.startsWith("0x") ? text.slice(2) : text
}
