.pragma library

// What a panel and a notification popup keep clear of: the bar and, beyond
// it, the dock. Panels and popups are Overlay surfaces that ignore every
// reserved zone, so the taskbar's own zone does nothing for them - the
// notification center ran down over the taskbar and hid the bell that opens
// it (round 12, V1). Pure numbers, so ShellPanel and the popup stack cannot
// disagree, and "a bottom bar with the dock beyond it" is a test rather than
// a screenshot.
//
// `dock` is { position, shown, reach, from, to } for the screen in question,
// or null while the dock is off: the callers never ask DockService then
// (pitfall 101). `from`/`to` are where its body runs along its edge, in the
// screen's own coordinates (`dockSpan`); without them it is the whole edge.

// Where a dock's body (DockService.bodies, in global coordinates) runs along
// its edge on a screen at `screenX`, `screenY`: { from, to }, or null.
function dockSpan(body, position, screenX, screenY) {
    if (!body || !isFinite(body.x) || !isFinite(body.y) || !(body.width > 0) || !(body.height > 0)) return null
    if (position === "left" || position === "right")
        return { from: body.y - (Number(screenY) || 0), to: body.y - (Number(screenY) || 0) + body.height }
    return { from: body.x - (Number(screenX) || 0), to: body.x - (Number(screenX) || 0) + body.width }
}

// How far a shown dock on `edge` reaches into its screen, else 0. Its reach
// is measured from its own surface's edge, which stands beyond a bar on the
// same edge (Dock.qml), so a bar's inset comes on top of it. `low`/`high`,
// when given, are where the thing that keeps clear of it runs along that
// edge: a dock that does not come up beside it (a floating dock in the
// middle, a panel in the corner) takes nothing - the panels would get
// shorter for a dock they never meet.
function dockReach(dock, edge, low, high) {
    if (!dock || dock.position !== edge || dock.shown !== true) return 0
    if (isFinite(low) && isFinite(high) && isFinite(dock.from) && isFinite(dock.to)
        && (Number(high) <= dock.from || Number(low) >= dock.to)) return 0
    return Math.max(0, Number(dock.reach) || 0)
}

// What a panel stays clear of along one edge: the bar on that edge, the dock
// beyond it and `gap`; with neither, the screen margin every panel keeps.
// `barInset` below zero is no bar on that edge. A bar alone gives what it
// always gave (its inset and the gap), so nothing moves without a dock.
function edgeClear(barInset, dockDepth, gap, margin) {
    const bar = Number(barInset)
    const dock = Math.max(0, Number(dockDepth) || 0)
    const space = Math.max(0, Number(gap) || 0)
    const edge = Math.max(0, Number(margin) || 0)
    if (isFinite(bar) && bar >= 0) return bar + dock + space
    if (dock > 0) return Math.max(edge, dock + space)
    return edge
}

// A popup's place `{ x, y }` (its size `width` x `height`) kept off a dock:
// on the dock's edge it stays `gap` beyond the dock and a bar on that edge.
// Only the dock's edge is touched - the bar and the notch already decided
// the rest - and a place that is clear already stays as it is. A bottom dock
// only moves a stack that grows up from a bottom bar: a stack hanging from
// the top would be pushed into the bar or the notch instead.
function clearOfDock(place, width, height, screenWidth, screenHeight, dock, barEdge, barInset, gap) {
    if (!place || !dock) return place
    const w = Math.max(0, Number(width) || 0)
    const h = Math.max(0, Number(height) || 0)
    const bar = String(barEdge)
    const inset = Math.max(0, Number(barInset) || 0)
    const space = Math.max(0, Number(gap) || 0)
    let x = Number(place.x), y = Number(place.y)
    const reach = (edge) => {
        const across = edge === "bottom" ? [x, x + w] : [y, y + h]
        const depth = dockReach(dock, edge, across[0], across[1])
        return depth > 0 ? depth + (bar === edge ? inset : 0) + space : 0
    }
    const bottom = reach("bottom"), left = reach("left"), right = reach("right")
    if (bottom > 0 && bar === "bottom") y = Math.min(y, Number(screenHeight) - h - bottom)
    if (right > 0) x = Math.min(x, Number(screenWidth) - w - right)
    if (left > 0) x = Math.max(x, left)
    if (x === Number(place.x) && y === Number(place.y)) return place
    return { x: Math.round(Math.max(0, x)), y: Math.round(Math.max(0, y)) }
}

// ---- opened by a key ------------------------------------------------------------
// A panel opened by a key or over IPC lands where its click would have
// opened it when the dock always shows the widget it belongs to: Super+N
// above the taskbar's bell instead of under a desktop clock a screen away
// (round 12, D13 g). The first of these the dock carries on that screen.
var DOCK_ITEMS = {
    notifications: ["notificationIndicator"],
    // The control center has no widget of its own on the Taskbar preset:
    // its status group stands for it, the volume in the middle first.
    controlCenter: ["quickPanel", "volume", "network", "battery", "bluetooth", "vpn"],
    dashboard: ["clock", "date"]
}
function dockItems(panelId) {
    return DOCK_ITEMS[panelId] || []
}

// Whether the arguments a panel was opened with already say where it goes:
// a pill, a widget, the notch or the dock that opened it. Those are left
// alone.
var PLACING_KEYS = ["anchorX", "anchorY", "anchorTop", "anchorBottom", "anchorLeft", "anchorRight", "originWidth"]
function placed(args) {
    if (!args) return false
    if (args.fromDock === true || args.fromNotch === true) return true
    return PLACING_KEYS.some(key => typeof args[key] === "number" && args[key] >= 0)
}

function validRect(rect) {
    return !!rect && isFinite(rect.x) && isFinite(rect.y) && rect.width > 0 && rect.height > 0
}

// The first of `types` that `lookup(type)` has a rectangle for, or null.
function firstRect(types, lookup) {
    for (const type of types || []) {
        const rect = lookup(type)
        if (validRect(rect)) return rect
    }
    return null
}

// `args` with the dock item's anchor (DockLogic.panelAnchor's answer for
// `rect`) and the item as the origin to grow out of, as a click passes them.
// Arguments that already place the panel come back unchanged.
function withDockItem(args, rect, anchor) {
    if (placed(args) || !validRect(rect) || !anchor || anchor.fromDock !== true) return args
    return Object.assign({}, args || {}, anchor, {
        originX: rect.x, originY: rect.y, originWidth: rect.width, originHeight: rect.height
    })
}
