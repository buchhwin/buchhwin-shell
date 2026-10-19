.pragma library

// What a panel and a notification popup keep clear of: the bar and, beyond
// it, the dock. Panels and popups are Overlay surfaces that ignore every
// reserved zone, so the taskbar's own zone does nothing for them - the
// notification center ran down over the taskbar and hid the bell that opens
// it. Pure numbers, so ShellPanel and the popup stack cannot
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
// The first of these the dock carries on that screen.
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

// ---- the surface -------------------------------------------------------------
// What a panel's layer surface covers (ShellPanel's `compactSurface`): the
// card and what it grows out of, not the screen. `full` is when it has to be
// the whole screen after all - a panel without a card (the overview draws
// the screen itself), a card being resized by its grip, or a card being
// dragged by its title. A panel that can be dragged is compact at rest:
// Settings, the only one, mapped a whole-screen surface for its 980 x 680
// card on every open (2.3 against 0.86 million pixels a frame on this
// laptop, 8.3 against 2.4 at a 4K desk), when it only needs the screen while
// it is being dragged. Once dragged it keeps the screen until it closes:
// shrinking a mapped surface lets a frame at the old size through (testing
// pitfall 57), and while the panel is open its surface only ever grows.
function fullSurface(compact, sizing, dragged) {
    return compact !== true || sizing === true || dragged === true
}

// The compact surface for a card at `card` ({ x, y, width, height }, where it
// settles) that grows out of `origin` (the same, or null): both, with `pad`
// around them for the shadow and the tooltips, inside the screen.
// `fullHeight` keeps the screen's whole height (a card that changes height
// while it is open). Whole pixels, never empty.
function cardSurface(card, origin, pad, screenWidth, screenHeight, fullHeight) {
    let x0 = card.x, y0 = card.y
    let x1 = card.x + card.width, y1 = card.y + card.height
    if (origin) {
        x0 = Math.min(x0, origin.x); y0 = Math.min(y0, origin.y)
        x1 = Math.max(x1, origin.x + origin.width); y1 = Math.max(y1, origin.y + origin.height)
    }
    x0 = Math.max(0, Math.floor(x0 - pad))
    y0 = Math.max(0, Math.floor(y0 - pad))
    x1 = Math.min(screenWidth, Math.ceil(x1 + pad))
    y1 = Math.min(screenHeight, Math.ceil(y1 + pad))
    if (fullHeight) { y0 = 0; y1 = screenHeight }
    return { x: x0, y: y0, width: Math.max(1, x1 - x0), height: Math.max(1, y1 - y0) }
}

// ---- out of a bar's pill ---------------------------------------------------------
// How far in from one side edge a panel that comes out of something may
// stand: `clear` (edgeClear's answer for that side), or less when it is only
// the screen `margin` and what the panel comes out of stands further out -
// the bar's last pill sits at the bar's own inset, a few pixels nearer the
// edge than the screen margin, and the panel out of it ended that much short
// of it, so no two edges lined up. A bar or a dock on that side is kept
// clear of whatever opened the panel. `originNear` is how far the origin is
// from that edge (negative: no origin).
function outerClear(clear, margin, originNear) {
    const near = Number(originNear)
    if (!isFinite(near) || near < 0 || clear > margin) return clear
    return Math.max(0, Math.min(clear, near))
}
