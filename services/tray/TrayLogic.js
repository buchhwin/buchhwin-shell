.pragma library

// The tray widget (shell/widgets/TrayWidget.qml) and the menu it opens out of
// an icon (shell/popups/TrayMenuPopup.qml). Pure functions, unit tested in
// TrayWidgetTest.qml.
//
// StatusNotifier items were reachable only through the control center's
// "Background apps" page, two clicks deep, so an icon's own state - unread,
// syncing, asking for attention - was never seen. The widget puts the icons
// on the bar, the notch or the desktop, wherever it is placed, and marks the
// ones asking for attention with a dot.

// SNI's Status, as Quickshell numbers it (Quickshell.Services.SystemTray
// Status: Passive, Active, NeedsAttention).
var PASSIVE = 0
var ACTIVE = 1
var NEEDS_ATTENTION = 2

// Passive is the item's own word for "nothing to see right now" (a phone
// that is not connected, an updater with nothing to do): the widget leaves
// it out, as every desktop's tray does, and the control center's page still
// lists it. `items` are { id, status } descriptors.
function shownIds(items, hiddenIds) {
    const hidden = hiddenIds || []
    return (items || []).filter(item => item && hidden.indexOf(item.id) < 0 && item.status !== PASSIVE)
        .map(item => item.id)
}

function attention(status) {
    return status === NEEDS_ATTENTION
}

// What an item is called: its tooltip's title, its title, or its id.
function label(item) {
    if (!item) return ""
    return String(item.tooltipTitle || item.title || item.id || "")
}

// What a click with `button` ("left", "middle", "right") does: "activate",
// "secondary" or "menu" - or "" for nothing. An item that says it has only a
// menu opens it on any click; a right click without a menu is the item's
// own activation, which some applications (KDE Connect's) use for their
// window.
function clickAction(button, onlyMenu, hasMenu) {
    if (button === "right") return hasMenu ? "menu" : "activate"
    if (button === "middle") return "secondary"
    if (onlyMenu) return hasMenu ? "menu" : ""
    return "activate"
}

// Where a layer surface sits on its screen, from its anchors and margins the
// way wlr-layer-shell places it: against an edge it is anchored to, and
// centred along an axis anchored on neither side or on both (stretched,
// where the margin is its offset). The widget maps an icon into its window
// and adds this to open the menu below it - a widget cannot see the origin
// its host reports with (the bar's reportOrigin), and a bottom bar's window
// is not at the top of the screen.
function surfaceOrigin(anchors, margins, size, screenSize) {
    const a = anchors || {}
    const m = margins || {}
    const width = Number(size && size.width) || 0
    const height = Number(size && size.height) || 0
    const screenWidth = Number(screenSize && screenSize.width) || 0
    const screenHeight = Number(screenSize && screenSize.height) || 0
    const along = (start, end, before, after, length, room) =>
        start ? (Number(before) || 0)
            : end ? room - length - (Number(after) || 0)
            : Math.round((room - length) / 2)
    return {
        x: along(a.left, a.right, m.left, m.right, width, screenWidth),
        y: along(a.top, a.bottom, m.top, m.bottom, height, screenHeight)
    }
}

// Which edge a surface hangs from: "top", "bottom", "left" or "right" for a
// bar, the notch or the dock, "" for one anchored on every side or on none
// (the desktop's widgets, a floating window).
function surfaceEdge(anchors) {
    const a = anchors || {}
    if (a.top && !a.bottom) return "top"
    if (a.bottom && !a.top) return "bottom"
    if (a.left && !a.right) return "left"
    if (a.right && !a.left) return "right"
    return ""
}

// The panel's arguments for a menu opened out of the icon at `rect` (screen
// coordinates): it grows out of the icon. In a bar or the notch the panel
// keeps its own place across it (`barAtEdge`: the screen's bar, or the notch,
// is on the edge the surface hangs from) - under a top bar or the notch,
// above a bottom bar, beside a side bar - which is what a pill's popup does
// (Pill.open); placed below the icon itself it would sit over the bar's lower
// half. Anywhere else - the desktop's widgets, a dock with no bar on its edge -
// it goes below the icon, or above it in the lower half of the screen, as
// WidgetFrame opens a desktop widget's panel.
function menuArgs(rect, screenHeight, gap, screenName, edge, barAtEdge) {
    const args = { originX: rect.x, originY: rect.y, originWidth: rect.width, originHeight: rect.height }
    if (edge === "left" || edge === "right") {
        args.anchorY = rect.y + rect.height / 2
    } else {
        args.anchorX = rect.x + rect.width / 2
        if (!(barAtEdge === true && (edge === "top" || edge === "bottom"))) {
            const lower = screenHeight > 0 && rect.y + rect.height / 2 > screenHeight / 2
            if (lower) args.anchorBottom = rect.y - gap
            else args.anchorTop = rect.y + rect.height + gap
        }
    }
    if (screenName) args.onScreen = screenName
    return args
}
