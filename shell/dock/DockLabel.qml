import QtQuick
import qs.theme
import qs.shell.components

// An app's name over its icon on the dock (beside it on a side dock), inside
// the room the dock's surface keeps for it - a tooltip window of its own
// would be a second surface, and ToolTipLayer only knows above and below.
// The look is the tooltips': solid surface, panel border, small text.
Rectangle {
    id: root

    property string edge: "bottom"
    // The icon it names, in the surface's coordinates; null hides it.
    property var anchorRect: null
    property string text: ""
    property bool shown: false
    // Kept inside its parent: a label on the dock's surface. The apps widget
    // puts it outside itself, into the room the dock keeps above it.
    property bool clampToArea: true

    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property Item area: parent

    visible: opacity > 0 && anchorRect !== null && text.length > 0
    opacity: shown && anchorRect !== null ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }

    width: Math.min(Metrics.dockLabelMaxWidth, name.implicitWidth + Metrics.spaceMd * 2)
    height: Metrics.dockLabelHeight
    radius: Metrics.radiusInner
    color: Colors.solidSurface
    border.width: Metrics.borderWidth
    border.color: Colors.panelBorder

    // Above the icon on a bottom dock, beside it on a side dock, and never
    // out of the surface.
    readonly property real wantedX: !anchorRect ? 0
        : edge === "left" ? anchorRect.x + anchorRect.width + Metrics.dockLabelGap
        : edge === "right" ? anchorRect.x - width - Metrics.dockLabelGap
        : anchorRect.x + anchorRect.width / 2 - width / 2
    readonly property real wantedY: !anchorRect ? 0
        : vertical ? anchorRect.y + anchorRect.height / 2 - height / 2
        : anchorRect.y - height - Metrics.dockLabelGap
    x: clampToArea ? Math.max(0, Math.min((area ? area.width : 0) - width, wantedX)) : wantedX
    y: clampToArea ? Math.max(0, Math.min((area ? area.height : 0) - height, wantedY)) : wantedY

    ShellText {
        id: name
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.width - Metrics.spaceMd * 2)
        text: root.text
        role: "small"
        elide: Text.ElideRight
    }
}
