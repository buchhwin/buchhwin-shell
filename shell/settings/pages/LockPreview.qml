import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.editor
import "../../../services/arrange/ArrangeLogic.js" as Arrange
import "../../../services/lock/LockCatalogue.js" as Lock

// A sketch of the lock screen, and the surface it is arranged on.
//
// Not the real lock screen: that one's whole job is to be modal, so editing it
// there would mean two full-screen surfaces owning the keyboard at once. The
// items are dragged and sized here, on a dark rectangle standing in for the
// wallpaper, and the lock screen reads the result the next time it comes up.
Rectangle {
    id: root
    readonly property var items: LayoutService.lockItems

    // The cells lean only while the pointer is over the sketch and Settings
    // is on screen. Always leaning, every cell's Wiggle redrew the whole
    // Settings surface on every frame for as long as the page was open, and
    // went on ticking for the minute the panel keeps a closed page; the frame
    // and the handles say "arrangeable" by themselves.
    readonly property bool leaning: activity.active && previewHover.hovered
    PageActivity { id: activity }
    HoverHandler { id: previewHover }

    implicitHeight: grid.implicitHeight + loginSketch.height + Metrics.spaceXl * 3
    radius: Metrics.radiusCard
    color: Colors.lockBase
    border.width: Metrics.borderWidth
    border.color: Colors.border
    clip: true

    // The drag needs a layer above the cells to carry the item being moved.
    Item { id: overlay; anchors.fill: parent; z: 5 }

    ArrangeArea {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Metrics.spaceLg
        height: implicitHeight
        columns: Arrange.columnsFor(width, Metrics.lockGridCell, Metrics.lockGridColumns)
        unit: Metrics.lockGridUnit
        gap: Metrics.spaceLg
        maxRows: LayoutService.gridMaxRows
        editing: true
        dragLayer: overlay
        model: root.items.map(item => ({ id: item.id, w: item.w, h: item.h,
            minW: Lock.minSize(item.type).w, minH: Lock.minSize(item.type).h }))
        onCommitted: (id, index) => LayoutService.lockMoveTo(id, index)

        Repeater {
            model: root.items
            ArrangeItem {
                id: cell
                required property var modelData
                required property int index
                area: grid
                itemId: modelData.id
                contentHeight: 1
                onResized: (w, h) => LayoutService.lockSetSize(cell.modelData.id, w, h)

                // Only the face leans, as on the other arranged surfaces: the
                // remove button and the corner handle stay where the hand
                // expects them.
                Item {
                    id: face
                    anchors.fill: parent
                    transform: Rotation {
                        origin.x: face.width / 2
                        origin.y: face.height / 2
                        angle: wiggle.angle
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.radiusInner
                        color: Colors.lockField
                        border.width: Metrics.borderWidth
                        border.color: Colors.border
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: Metrics.spaceSm
                        ShellIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: Lock.icon(cell.modelData.type)
                            size: Metrics.iconMd
                            color: Colors.lockText
                        }
                        ShellText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Lock.label(cell.modelData.type)
                            color: Colors.lockText
                        }
                    }
                }
                // Editable, so it says so while the pointer is over it - each
                // cell at its own point of the cycle, and still while it is
                // under the hand.
                Wiggle {
                    id: wiggle
                    index: cell.index
                    running: grid.editing && root.leaning && !cell.dragging && !cell.sizing
                }
                // In the lock screen's own inks, whatever the theme: the
                // danger wash and glyph are made for a light or dark card, and
                // on this always-dark tile the light theme's dark red was
                // 1.2:1. The fills are the lock face's power button's (a field
                // that lightens under the pointer), which keep its error red
                // above 3:1 both ways. The glyph is drawn here, over a button
                // with no icon of its own, because a button takes its glyph's
                // colour from its variant.
                ShellButton {
                    id: removeBadge
                    focusOnTab: true
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: Metrics.spaceXxs
                    z: 3
                    compact: true
                    color: removeBadge.hovered || removeBadge.down ? Colors.lockButton : Colors.lockField
                    toolTip: "Take off the lock screen"
                    onClicked: LayoutService.lockRemove(cell.modelData.id)
                    ShellIcon {
                        anchors.centerIn: parent
                        glyph: Icons.remove
                        size: removeBadge.iconSize
                        color: Colors.lockError
                    }
                }
            }
        }
    }

    // Where the login block sits, so the arrangement above it can be judged.
    // It is not arranged: the animation that carries it to the centre while
    // you type is an anchor margin, and an arranged cell is an x and a y.
    Column {
        id: loginSketch
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.spaceLg
        spacing: Metrics.spaceXs
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Metrics.iconXl
            height: width
            radius: width / 2
            color: Colors.lockField
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Metrics.lockFieldWidth / 2
            height: Metrics.controlHeightSm
            radius: height / 2
            color: Colors.lockField
        }
        ShellText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Password"
            color: Colors.lockMuted
            role: "caption"
        }
    }
}
