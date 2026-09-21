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

    function show(item, text) {
        if (!item || !text || !text.length) return
        layer.target = item
        layer.label = text
    }

    // Only the control that is showing may take the bubble away, or a control
    // the pointer has already left would close the one that replaced it.
    function hide(item) {
        if (item !== null && item !== layer.target) return
        layer.target = null
        layer.label = ""
    }

    // Where the control is in this layer's coordinates. Read once, when the
    // target changes: a control does not move while the pointer rests on it,
    // and a position that animated would drag the bubble around with it.
    readonly property var spot: {
        if (!target || !target.width) return null
        const point = layer.mapFromItem(target, 0, 0)
        return { x: point.x, y: point.y, width: target.width, height: target.height }
    }

    // Where the bubble goes: centred on the control and below it, flipped above
    // when there is no room, and always kept inside the window - a bubble half
    // off the edge says less than none at all. Worked out here rather than in
    // the rectangle so it can be held to account by a test.
    readonly property bool above: spot !== null
        && spot.y + spot.height + bubble.height + Metrics.spaceXs > layer.height
    readonly property real bubbleX: spot === null ? 0
        : Math.max(Metrics.spaceXs, Math.min(layer.width - bubble.width - Metrics.spaceXs,
                                             spot.x + spot.width / 2 - bubble.width / 2))
    readonly property real bubbleWidth: bubble.width
    readonly property real bubbleY: spot === null ? 0
        : above ? spot.y - bubble.height - Metrics.spaceXs
                : spot.y + spot.height + Metrics.spaceXs

    Rectangle {
        id: bubble
        opacity: layer.spot !== null && layer.label.length > 0 ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
        x: layer.bubbleX
        y: layer.bubbleY
        width: label.implicitWidth + Metrics.spaceSm * 2
        height: label.implicitHeight + Metrics.spaceXs * 2
        radius: Metrics.radiusSm
        color: Colors.solidSurface
        border.width: Metrics.borderWidth
        border.color: Colors.panelBorder

        ShellText {
            id: label
            anchors.centerIn: parent
            text: layer.label
            role: "small"
        }
    }
}
