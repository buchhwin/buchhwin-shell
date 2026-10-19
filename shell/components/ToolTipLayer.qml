import QtQuick
import qs.theme

// One tooltip bubble per window, shown for whichever control asked last.
//
// A layer per window rather than a popup per control. Two earlier attempts went
// the other way and were both taken out again: a PopupWindow per button never
// appeared and took the shell down when several existed at once, and a Loader
// reparented onto a window found `QsWindow.window` still null at
// Component.onCompleted. A control finds this layer by walking up its own
// parents when the pointer arrives, by which time every window is long built.
//
// The window puts one of these on an unclipped layer above its content and
// points an ancestor of that content at it (`property Item toolTipLayer`), so
// the walk has something to find. A window without one simply shows no
// tooltips, which is what every window did before.
Item {
    id: layer
    anchors.fill: parent
    // Decoration: it must never take the pointer away from the control it is
    // describing, and a tooltip under the cursor would flicker forever.
    visible: bubble.opacity > 0

    // The control the bubble belongs to, and what it says. Held rather than
    // bound, because the control is what knows when the pointer arrived.
    property Item target: null
    property string label: ""
    // What the bubble shows, kept while it fades out: `hide` clears `target`
    // and `label` at once, and the fading bubble used to fall back to the
    // window's corner as an empty plate for the whole fade. Only `show`
    // writes these.
    property var shownSpot: null
    property string shownLabel: ""
    // The part of this layer the window really shows, in the layer's own
    // coordinates. A panel's layer is the size of the screen while its
    // surface is the card and a little room around it (ShellPanel's
    // `compactSurface`), so a long bubble kept inside the screen could
    // still run past the surface's edge and be cut off. Read at `show`:
    // a panel's surface holds still while it is open.
    property var shownBounds: ({ x: 0, y: 0, width: 0, height: 0 })

    function show(item, text) {
        if (!item || !text || !text.length) return
        layer.target = item
        layer.label = text
        layer.shownLabel = text
        layer.shownBounds = layer.windowBounds()
    }

    // Only the control that is showing may take the bubble away, or a control
    // the pointer has already left would close the one that replaced it.
    function hide(item) {
        if (item !== null && item !== layer.target) return
        layer.target = null
        layer.label = ""
    }

    // The wait before a bubble appears: one for the whole window, which the
    // control under the pointer starts (`ToolTipHost.arm`) and every way out
    // stops, rather than a Timer built into each of the hundreds of controls
    // that may show a bubble. Started and stopped by hand: a Timer that does
    // not repeat clears its own `running` when it fires, so a binding on it
    // is torn down at the very moment it matters.
    property ToolTipHost pending: null
    function arm(host) {
        if (!host) return
        layer.pending = host
        wait.interval = host.delay
        wait.restart()
    }
    function disarm(host) {
        if (host !== layer.pending) return
        wait.stop()
        layer.pending = null
    }
    Timer {
        id: wait
        onTriggered: {
            const host = layer.pending
            layer.pending = null
            if (host) host.show()
        }
    }

    // The window's visible part: from where the window starts in this
    // layer to where it ends, inside the layer. Outside a window (a test
    // that lays the layer out on its own) the layer itself.
    function windowBounds() {
        const w = layer.Window.width, h = layer.Window.height
        if (!(w > 0) || !(h > 0)) return { x: 0, y: 0, width: layer.width, height: layer.height }
        const origin = layer.mapFromItem(null, 0, 0)
        const x0 = Math.max(0, origin.x), y0 = Math.max(0, origin.y)
        const x1 = Math.min(layer.width, origin.x + w), y1 = Math.min(layer.height, origin.y + h)
        return { x: x0, y: y0, width: Math.max(0, x1 - x0), height: Math.max(0, y1 - y0) }
    }

    // Where the control is in this layer's coordinates. Read once, when the
    // target changes: a control does not move while the pointer rests on it,
    // and a position that animated would drag the bubble around with it.
    readonly property var spot: {
        if (!target || !target.width) return null
        const point = layer.mapFromItem(target, 0, 0)
        return { x: point.x, y: point.y, width: target.width, height: target.height }
    }
    onSpotChanged: if (spot !== null) shownSpot = spot

    // Where the bubble goes: centred on the control and below it, flipped above
    // when there is no room, and always kept inside what the window shows - a
    // bubble half off the edge says less than none at all. Worked out here
    // rather than in the rectangle so it can be held to account by a test.
    readonly property bool above: shownSpot !== null
        && shownSpot.y + shownSpot.height + bubble.height + Metrics.spaceXs > shownBounds.y + shownBounds.height
    readonly property real bubbleX: shownSpot === null ? 0
        : Math.max(shownBounds.x + Metrics.spaceXs,
                   Math.min(shownBounds.x + shownBounds.width - bubble.width - Metrics.spaceXs,
                            shownSpot.x + shownSpot.width / 2 - bubble.width / 2))
    readonly property real bubbleWidth: bubble.width
    readonly property real bubbleY: shownSpot === null ? 0
        : above ? shownSpot.y - bubble.height - Metrics.spaceXs
                : shownSpot.y + shownSpot.height + Metrics.spaceXs
    readonly property real bubbleOpacity: bubble.opacity

    Rectangle {
        id: bubble
        // Shown while a control holds it; on the way out it fades where it
        // was, with what it said (`shownSpot`, `shownLabel`).
        opacity: layer.spot !== null && layer.label.length > 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
        x: layer.bubbleX
        y: layer.bubbleY
        // As wide as the words, up to a cap and never wider than the window;
        // past that they wrap. One unbroken line had no limit at all.
        width: label.width + Metrics.spaceSm * 2
        height: label.height + Metrics.spaceXs * 2
        // A semantic radius like every other surface, so the corner setting
        // moves it with the rest: a bubble of one line of small print is the
        // size of a thumbnail or a swatch, not of a card.
        radius: Metrics.radiusInner
        color: Colors.solidSurface
        border.width: Metrics.borderWidth
        border.color: Colors.panelBorder

        ShellText {
            id: label
            x: Metrics.spaceSm
            y: Metrics.spaceXs
            width: Math.min(implicitWidth, Metrics.toolTipMaxWidth,
                            Math.max(0, layer.shownBounds.width - Metrics.spaceXs * 2 - Metrics.spaceSm * 2))
            text: layer.shownLabel
            role: "small"
            wrapMode: Text.Wrap
        }
    }
}
