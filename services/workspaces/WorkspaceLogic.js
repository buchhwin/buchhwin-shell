.pragma library
.import "../display/DisplayLogic.js" as Display

// Workspace indicator (widget and pill): which workspace numbers to show and
// their state. Pure functions, unit tested in WorkspaceTest.qml.

var minCount = 1
var maxCount = 10
var defaultCount = 5

var MODES = ["open", "gapless", "fixed"]

// How a workspace is drawn.
//   numbers    every one shows its number, as it always did
//   dots       none of them do; the row becomes a row of pips
//   pills      none of them do either, drawn as narrow standing capsules with
//              the active one wider - the island's strip
//   activeDot  the active one is a dot and the rest keep their numbers, so
//              where you are reads at a glance and where you could go is still
//              named
var STYLES = ["numbers", "dots", "pills", "activeDot"]

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
    case "pills": return false
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
// A workspace on its way out. Hyprland destroys an empty workspace in the
// same call that leaves it, but the shell hears the two halves apart: the new
// one comes and is shown (`createworkspace`, `workspace`) ~2 ms before the
// old one goes (`destroyworkspace`) - a nested trace of 1 → 2 → 3 had the row
// at "1 2 3" for those 2 ms, and a frame that fell in them drew a third pip
// and moved the notch for nothing. One with no window at all
// (`toplevels`, every window - a helper the row does not count still keeps a
// workspace alive), not the one its screen shows, and not held open
// (`kept`: the setting, or a persistent rule) is already gone. Unknown counts
// and an unknown active one leave everything as it was.
function leaving(item, activeId) {
    const active = Number(activeId)
    return !!item && active > 0 && item.id !== active && item.kept !== true
        && item.toplevels !== undefined && item.toplevels !== null && Number(item.toplevels) === 0
}

// A workspace from another monitor's block that is empty and not shown, with
// the blocks on (`blocks`): after an undock with "Keep empty workspaces open"
// every held workspace of the gone screens lands on the laptop, and the row
// grew by each of them (11, 12, 13, 21, 22 ...). They are still held and go
// back with their monitor; the overview still shows them for its ×. One
// with a window, the one shown and a named one stay. Without the blocks a
// high number is no stray at all, only a workspace past ten.
function idleStray(item, base, activeId, blocks) {
    if (blocks !== true || !item) return false
    const named = String(item.name || "") !== String(item.id)
    const mine = item.id > base && item.id <= base + perMonitorBlock
    return !named && !mine && item.id !== Number(activeId) && !(Number(item.windows) > 0)
}

// workspaces: [{ id, name, windows, screen, toplevels?, kept? }]; ids <= 0
// (special) are ignored, and so is one `leaving` or, with `blocks`, an
// `idleStray`. Returns [{ id, label, name, active, focused, occupied }]
// sorted by id; never empty. `label` is what to draw: a named workspace keeps
// its name, everything else shows the number *of its own monitor*.
function entries(mode, count, workspaces, screen, activeId, offset, focusedId, blocks) {
    const base = Math.max(0, Math.round(Number(offset)) || 0)
    const existing = (Array.isArray(workspaces) ? workspaces : [])
        .filter(item => item && typeof item.id === "number" && item.id > 0 && !leaving(item, activeId)
                && !idleStray(item, base, activeId, blocks))
    const byId = {}
    for (const item of existing) byId[item.id] = item
    const onScreen = existing.filter(item => item.screen === screen).map(item => item.id)

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
// the wrong question: with three monitors a workspace *is* a monitor.
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
// by name so two monitors at the same place still get a stable answer - with
// a laptop panel after every other screen while one is on.
//
// By *position*, because that is the order the Displays page numbers its
// rectangles in (`DisplayLogic.parseMonitors` sorts the same way) and the
// Identify overlay shows. Monitor 1 has to be the same monitor everywhere or
// the numbers are worse than none.
//
// Except for the panel at a desk. It comes and goes with the lid, and
// Hyprland's automatic layout puts it first (x 0), so numbered by its place it
// took the first block whenever the lid was open: opening the lid moved every
// block of workspaces, windows and all, one screen on, and closing it moved
// them back. Last, the desk's screens keep their blocks with the lid open or
// shut; a laptop on its own is unchanged. The Displays page still numbers by
// place, so with the lid open at a desk the panel's number there is not its
// block's.
function monitorOrder(monitors) {
    const list = (Array.isArray(monitors) ? monitors : [])
        .filter(item => item && typeof item.name === "string" && item.name.length)
    const panelLast = list.some(item => !Display.isInternal(item.name))
    const rank = item => panelLast && Display.isInternal(item.name) ? 1 : 0
    return list.slice()
        .sort((a, b) => rank(a) - rank(b)
            || (Number(a.x) || 0) - (Number(b.x) || 0)
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

// Which workspace each screen shows once the moves are done, as
// `[{ monitor, id }]` for the screens that need telling. This is the half
// `misplaced` cannot do. `actives` is `[{ monitor, id }]` as the screens
// stand before the moves, `placed` the workspaces as `misplaced` takes them
// (`windows`, their window count, where known) and `moves` its answer.
// Unit tested.
//
// A screen whose workspace is moved away, or that shows another block's: the
// one of its own that some screen was showing (the view follows the
// workspace it was on - docking moved 5 to the new first screen, and that
// screen was sent to 3, the lowest of its own), else the lowest of its own,
// else its first. Moving a workspace off a monitor leaves it empty, and
// Hyprland fills an empty monitor at once with the next free number - 2 on
// the third screen after a reboot (2026-10-13) - which no monitor change ever
// came back to look at.
//
// And a screen a workspace is moved *to*: Hyprland shows the moved one there
// without a word to the shell (no `workspace` event), so at a login with
// three monitors the first one was left on 3 while the shell and its pips
// said 1. It goes back to its own - unless one of the arrivals has windows
// and was on screen, which is somebody's work arriving.
//
// A screen showing a workspace from beyond the blocks (a monitor that is
// gone: undock, and Hyprland hands 11-20 to the laptop with their ids) is
// left alone, the same rule `misplaced` keeps. Those are the stray pips
// `entries` draws to be visited, and sending the screen home sent it away
// 400 ms after the next workspace came or went - leaving an emptied one is
// enough - so the undocked monitor's windows could not be stayed with.
function views(order, placed, actives, moves) {
    const monitors = Array.isArray(order) ? order : []
    const moving = (Array.isArray(moves) ? moves : []).filter(move => move && typeof move.monitor === "string")
    const movedIds = moving.map(move => Math.round(Number(move.id)))
    const workspaces = (Array.isArray(placed) ? placed : []).filter(Boolean)
    const ids = workspaces.map(item => Math.round(Number(item.id))).filter(id => id >= 1)
    const shown = (Array.isArray(actives) ? actives : []).filter(Boolean)
        .map(active => Math.round(Number(active.id))).filter(id => id >= 1)
    const windowsOf = id => {
        const item = workspaces.find(other => Math.round(Number(other.id)) === id)
        return item ? Number(item.windows) || 0 : 0
    }
    const result = []
    for (const active of (Array.isArray(actives) ? actives : [])) {
        if (!active) continue
        const index = monitors.indexOf(String(active.monitor || ""))
        if (index < 0) continue
        const name = monitors[index]
        const id = Math.round(Number(active.id))
        const valid = isFinite(id) && id >= 1 && movedIds.indexOf(id) < 0
        const own = ids.filter(other => monitorIndexOf(other) === index).sort((a, b) => a - b)
        if (moving.some(move => move.monitor === name)) {
            const arriving = movedIds.filter(other => monitorIndexOf(other) === index
                                             && shown.indexOf(other) >= 0 && windowsOf(other) > 0)
            if (arriving.length) { result.push({ monitor: name, id: Math.min.apply(null, arriving) }); continue }
            if (valid && (monitorIndexOf(id) === index || monitorIndexOf(id) >= monitors.length)) {
                result.push({ monitor: name, id: id })
                continue
            }
        } else if (valid && (monitorIndexOf(id) === index || monitorIndexOf(id) >= monitors.length)) {
            continue
        }
        const seen = own.filter(other => shown.indexOf(other) >= 0)
        result.push({ monitor: name, id: seen.length ? seen[0] : own.length ? own[0] : globalId(1, index) })
    }
    return result
}

// `views` for screens without moves: `actives` with -1 for a workspace that
// is being moved away (the form it had before the moves were its business).
function homes(order, placed, actives) {
    return views(order, placed, actives, [])
}

// ---- The neighbouring workspace (Super+Page Up/Down, Super+wheel) ---------
//
// Where a step goes from `activeId` on one monitor: `pips` are that
// monitor's `entries` - what its row shows in the session's mode, so a step
// lands on the pip beside the lit one, the way the eye already went -
// `direction` is +1 for the next and -1 for the previous one, and `base`
// is where the monitor's block starts (`offsetFor`). Past the last pip there
// is one new workspace, and only from one that has windows: GNOME's one
// empty workspace at the end, never a march into nothing with a wheel that
// keeps turning, and never out of the monitor's own block, which would land
// on another screen's numbers. No wrap at either end, as on Windows and
// GNOME. 0 for nowhere to go.
function step(pips, activeId, direction, base) {
    const dir = Number(direction)
    const active = Math.round(Number(activeId))
    if (!isFinite(dir) || dir === 0 || !isFinite(active) || active < 1) return 0
    const list = (Array.isArray(pips) ? pips : []).filter(item => item && typeof item.id === "number" && item.id > 0)
    const ids = list.map(item => item.id).sort((a, b) => a - b)
    const beyond = dir > 0 ? ids.filter(id => id > active) : ids.filter(id => id < active).reverse()
    if (beyond.length) return beyond[0]
    const current = list.find(item => item.id === active)
    if (!current || current.occupied !== true) return 0
    const start = Math.max(0, Math.round(Number(base)) || 0)
    const next = active + (dir > 0 ? 1 : -1)
    return next > start && next <= start + perMonitorBlock ? next : 0
}

// The ids the per-monitor rules were sent for: every block up to the
// highest one sent since the last config reload (HyprlandService.ruledUpTo).
// The highest, not the current monitors': a monitor unplugged since keeps
// its block's rules, and they would bind 11-20 to it when it returns.
function ruledIds(upTo) {
    const count = Math.round(Number(upTo))
    const ids = []
    for (let id = 1; isFinite(count) && id <= count; ++id) ids.push(id)
    return ids
}

// ---- Empty workspaces held open (workspaces.keepEmpty) ------------------------
//
// Hyprland forgets an empty workspace the moment no monitor shows it. With the
// setting on, the shell holds each one open with a `persistent` rule, and the
// overview's × closes it again.

// Where a closed workspace's windows go, and the view with them: the one
// before it on its monitor, else the one after; -1 when it is the monitor's
// only one, which has nothing to close into (and no ×). `siblings` are the
// ids on that monitor.
function closeTarget(siblings, id) {
    const ids = (Array.isArray(siblings) ? siblings : [])
        .filter(item => typeof item === "number" && isFinite(item) && item > 0)
        .filter((item, index, list) => list.indexOf(item) === index)
        .sort((a, b) => a - b)
    const at = ids.indexOf(Number(id))
    if (at < 0 || ids.length < 2) return -1
    return at > 0 ? ids[at - 1] : ids[at + 1]
}

// What to hold open now, as { id: monitor }: each workspace that may stay
// where it is, with the monitor it is on. A persistent rule names a monitor,
// and Hyprland moves a workspace standing on another one there; the monitor
// left empty gets the next free number - which was held open in turn, moved,
// and the next one after it: a nested run had 670 workspaces within seconds
// So the rule always names the monitor the workspace is on, and
// nothing is held that has no monitor yet, that the per-monitor blocks are
// about to move (`order`: the monitors' order with workspaces.perMonitor on,
// else empty), that is being closed, or past `limit` workspaces held.
// `existing` is [{ id, monitor }], `kept` the { id: monitor } sent so far; a
// kept one whose monitor changed is sent again with the new one.
function keepPlan(existing, kept, closing, order, limit) {
    const held = kept && typeof kept === "object" ? kept : {}
    const going = Array.isArray(closing) ? closing : []
    const cap = Math.max(0, Math.round(Number(limit)) || 0)
    const list = (Array.isArray(existing) ? existing : [])
        .filter(item => item && typeof item.id === "number" && item.id > 0
                && String(item.monitor || "").length > 0 && going.indexOf(item.id) < 0)
        .sort((a, b) => a.id - b.id)
    const wrong = misplaced(order, list).map(move => move.id)
    const plan = {}
    let count = Object.keys(held).length
    for (const item of list) {
        if (wrong.indexOf(item.id) >= 0 || held[item.id] === item.monitor || plan[item.id] !== undefined) continue
        if (held[item.id] === undefined) {
            if (count >= cap) continue
            count += 1
        }
        plan[item.id] = String(item.monitor)
    }
    return plan
}

// Whether a workspace stays when it is empty and not shown - WorkspaceWidget's
// `kept`, which `leaving` spares. With the setting on (`keepEmpty`): one the
// shell holds (`kept`, the { id: monitor } it sent) or a persistent rule
// holds (`persistent`, Hyprland's `ispersistent`), never one the × is
// closing. Counting every workspace as held while the setting was on, the
// ones the limit left unheld too, brought the third pip of a passing switch
// back for those (Super+2, then Super+3, from an empty 1). Off: the
// persistent rule alone.
function isKept(id, keepEmpty, kept, closing, persistent) {
    const number = Math.round(Number(id))
    if (keepEmpty !== true) return persistent === true
    if (Array.isArray(closing) && closing.indexOf(number) >= 0) return false
    return persistent === true || (!!kept && typeof kept === "object" && kept[number] !== undefined)
}

// How many workspaces may be held open at most: a block per monitor and one
// more. Only a person opens them, one key at a time; past this something is
// opening them on its own, and holding each would feed it.
function keepLimit(monitors) {
    const count = Math.round(Number(monitors))
    return perMonitorBlock * (isFinite(count) && count > 0 ? count : 1) + perMonitorBlock
}
