.pragma library

// Workspace indicator (widget and pill): which workspace numbers to show and
// their state. Pure functions, unit tested in WorkspaceTest.qml.

var minCount = 1
var maxCount = 10
var defaultCount = 5

var MODES = ["open", "gapless", "fixed"]

// How a workspace is drawn.
//   numbers    every one shows its number, as it always did
//   dots       none of them do; the row becomes a row of pips
//   activeDot  the active one is a dot and the rest keep their numbers, so
//              where you are reads at a glance and where you could go is still
//              named
var STYLES = ["numbers", "dots", "activeDot"]

function normalizeStyle(style) {
    return STYLES.indexOf(style) >= 0 ? style : "numbers"
}

// Whether this workspace shows its name. A workspace the user has *named*
// keeps it whatever the style says: a name is not a number, somebody chose it,
// and turning "web" into a dot throws away the only thing that made it worth
// naming.
function showsLabel(style, entry) {
    const item = entry || {}
    const named = String(item.name || "") !== String(item.id)
    if (named) return true
    switch (normalizeStyle(style)) {
    case "dots": return false
    case "activeDot": return !item.active
    default: return true
    }
}

function normalizeMode(mode) {
    return MODES.indexOf(mode) >= 0 ? mode : "open"
}

// Every number from the lowest of `ids` to the highest, so a workspace that
// has emptied out between two that have not does not vanish and take the
// numbering with it.
//
// Hyprland forgets a workspace the moment its last window closes, which is
// right for the compositor and wrong for a row of numbers: close everything on
// 2 while 1 and 3 are in use and the row silently becomes "1 3", so the thing
// you were about to switch back to is no longer there to click. Filling the
// span costs nothing - the workspaces it names are one dispatch away whether
// or not anybody is drawing them.
//
// Only the span, never beyond it: an empty workspace *after* the last occupied
// one is the next one, and that is the picker's job, not this one's.
function spanIds(ids) {
    const numbers = (Array.isArray(ids) ? ids : []).filter(id => typeof id === "number" && isFinite(id) && id > 0)
    if (!numbers.length) return []
    const lowest = Math.min.apply(null, numbers)
    const highest = Math.max.apply(null, numbers)
    const result = []
    for (let id = lowest; id <= highest; ++id) result.push(id)
    return result
}

function normalizeCount(count) {
    const value = Math.round(Number(count))
    return isFinite(value) ? Math.max(minCount, Math.min(maxCount, value)) : defaultCount
}

// mode "open": the existing workspaces of this screen (Hyprland keeps a
// workspace while it has windows or is shown). mode "gapless": the same, with
// the empty ones between them filled back in. mode "fixed": always 1…count of
// *this monitor's block*, plus existing workspaces of this screen above it.
//
// `offset` is where this monitor's block of ten starts (0 for the first
// monitor, or always 0 when workspaces are not per monitor - see
// `offsetFor`). Before it existed, `fixed` built 1…count and never looked at
// `screen` at all, so three monitors showed the same three numbers and
// clicking 3 on one of them moved the focus to another.
//
// `activeId` is the workspace *this monitor* is showing, not the globally
// focused one: with three bars, comparing against the global focus left two of
// them with no active pip at all. `focusedId` still marks the one that has the
// keyboard.
//
// workspaces: [{ id, name, windows, screen }]; ids <= 0 (special) are ignored.
// Returns [{ id, label, name, active, focused, occupied }] sorted by id; never
// empty. `label` is what to draw: a named workspace keeps its name, everything
// else shows the number *of its own monitor*.
function entries(mode, count, workspaces, screen, activeId, offset, focusedId) {
    const existing = (Array.isArray(workspaces) ? workspaces : [])
        .filter(item => item && typeof item.id === "number" && item.id > 0)
    const byId = {}
    for (const item of existing) byId[item.id] = item
    const onScreen = existing.filter(item => item.screen === screen).map(item => item.id)
    const base = Math.max(0, Math.round(Number(offset)) || 0)

    const wanted = normalizeMode(mode)
    let ids = []
    if (wanted === "fixed") {
        const limit = normalizeCount(count)
        for (let id = 1; id <= limit; ++id) ids.push(base + id)
        ids = ids.concat(onScreen.filter(id => id > base + limit || id < base + 1))
    } else if (wanted === "gapless") {
        ids = spanIds(onScreen)
    } else {
        ids = onScreen
    }
    // No workspace known yet (startup): show this monitor's first so the pill
    // keeps its place.
    const placeholder = ids.length === 0
    if (placeholder) ids = [base + 1]

    const active = Number(activeId)
    const focused = Number(focusedId)
    return ids.filter((id, index) => ids.indexOf(id) === index)
        .sort((a, b) => a - b)
        .map(id => {
            const item = byId[id]
            const name = item && item.name ? String(item.name) : String(id)
            const named = name !== String(id)
            // A workspace whose id belongs to *another* monitor's block shows
            // its real number. Unplug a screen and Hyprland moves its
            // workspaces onto a survivor; if 11 were drawn as "1" there would
            // be two pips claiming the same place, and clicking either would
            // be a coin toss. Showing 11 says plainly "this one is not yours",
            // which is the truth and needs nothing done to the user's windows.
            const mine = id > base && id <= base + perMonitorBlock
            return {
                id: id,
                name: name,
                label: named ? name : String(mine ? localId(id) : id),
                stray: !named && !mine,
                active: id === active || (placeholder && !(active > 0)),
                focused: id === focused,
                occupied: !!item && Number(item.windows) > 0
            }
        })
}

// ---- Workspaces per monitor -------------------------------------------------
//
// Hyprland has one global set of workspaces and gives each of them a monitor.
// That makes `Super+3` mean "go to whichever screen is holding 3", which is
// what the user called blöd: with three monitors a workspace *is* a monitor.
//
// Per-monitor sets, without a plugin: give each monitor a block of ten ids and
// let the keys act on the monitor under the focus. Monitor 1 keeps 1-10, so a
// single-screen session is unchanged down to the numbers in `hyprctl`; monitor
// 2 gets 11-20, monitor 3 gets 21-30. The bar keeps showing 1-9, because the
// number a user cares about is which of *their* workspaces it is.
//
// Nothing here is a plugin's job: hyprsplit and split-monitor-workspaces do
// the same arithmetic, and one would have to be built against this exact
// Hyprland commit.
var perMonitorBlock = maxCount

// The order monitors are numbered in: left to right, then top to bottom, then
// by name so two monitors at the same place still get a stable answer.
//
// By *position*, because that is the order the Displays page numbers its
// rectangles in (`DisplayLogic.parseMonitors` sorts the same way) and the
// Identify overlay shows. Monitor 1 has to be the same monitor everywhere or
// the numbers are worse than none.
function monitorOrder(monitors) {
    return (Array.isArray(monitors) ? monitors : [])
        .filter(item => item && typeof item.name === "string" && item.name.length)
        .slice()
        .sort((a, b) => (Number(a.x) || 0) - (Number(b.x) || 0)
            || (Number(a.y) || 0) - (Number(b.y) || 0)
            || String(a.name).localeCompare(String(b.name)))
        .map(item => String(item.name))
}

function monitorIndex(monitors, name) {
    const index = monitorOrder(monitors).indexOf(String(name))
    return index < 0 ? 0 : index
}

// The id a monitor's own workspace `local` has in the compositor.
function globalId(localId, index) {
    const local = Math.round(Number(localId))
    const slot = Math.round(Number(index))
    if (!isFinite(local) || local < 1) return 0
    return (isFinite(slot) && slot > 0 ? slot : 0) * perMonitorBlock + local
}

// And back: which of a monitor's own numbers this is, and whose it is.
function localId(id) {
    const value = Math.round(Number(id))
    if (!isFinite(value) || value < 1) return 0
    return ((value - 1) % perMonitorBlock) + 1
}

function monitorIndexOf(id) {
    const value = Math.round(Number(id))
    if (!isFinite(value) || value < 1) return 0
    return Math.floor((value - 1) / perMonitorBlock)
}

// The offset a monitor's block starts at, for `entries`.
function offsetFor(monitors, name) {
    return monitorIndex(monitors, name) * perMonitorBlock
}

// The workspaces that sit on a monitor other than the one their block names,
// as `[{ id, monitor }]` moves - the rule only binds a workspace *when it is
// created*, and Hyprland creates one per monitor before the shell has said a
// word: after every reboot, 3 stood on the second screen and 4 on the third,
// "the workspaces are jumbled again". A workspace beyond the blocks (a
// monitor that is gone) and the special ones (id < 1) are left where they
// are; the rest are moved once the rules are in.
function misplaced(order, workspaces) {
    const monitors = Array.isArray(order) ? order : []
    const moves = []
    for (const workspace of (Array.isArray(workspaces) ? workspaces : [])) {
        if (!workspace) continue
        const id = Math.round(Number(workspace.id))
        if (!isFinite(id) || id < 1) continue
        const index = monitorIndexOf(id)
        if (index >= monitors.length) continue
        const wanted = monitors[index]
        if (typeof wanted !== "string" || !wanted.length) continue
        if (String(workspace.monitor || "") === wanted) continue
        moves.push({ id: id, monitor: wanted })
    }
    return moves.sort((a, b) => a.id - b.id)
}
