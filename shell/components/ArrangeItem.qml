import QtQuick
import qs.theme
import qs.services
import "../../services/arrange/FitLogic.js" as Fit

// One item on an ArrangeArea. It takes its place from the area rather than
// from a layout, so a neighbour can glide aside to open a gap.
//
// The press threshold, the single undo step and the write-on-release all live
// here, which is the difference from what the control center used to do: it
// rewrote and saved the model on every pointer move, so one drag cost eight
// undo steps and eight writes of layout.json.
Item {
    id: item

    required property string itemId
    required property ArrangeArea area
    property bool draggable: true
    // A surface the user sizes hands back what a corner was pulled to; the
    // caller writes it. `resizable` is false where a cell's size is not the
    // user's - a list, a single column.
    property bool resizable: area !== null && area.sized
    signal resized(int w, int h)
    // What the item is worth in height when it is at rest. The area collects
    // these and hands back a place; the two are separate properties on purpose,
    // because binding one to the other is a loop.
    property real contentHeight: 0

    readonly property var cell: area ? area.cellOf(itemId) : null
    readonly property bool dragging: area && area.dragging && area.dragId === itemId

    // The size the packer granted this cell, in grid steps, and the shape that
    // follows from it. Content that draws differently at different sizes reads
    // these rather than measuring pixels it would have to know the surface to
    // interpret. They are live while a corner is pulled, because the area
    // re-packs the whole grid at the wanted size, so a tile rearranges under
    // the hand instead of after the release.
    //
    // Before the first placement there is no cell, and on a surface that is
    // not sized there are no steps at all: `small` is the answer that is wrong
    // in no direction, and it is what a tile starts as.
    readonly property int gridW: cell && cell.w ? cell.w : 1
    readonly property int gridH: cell && cell.h ? cell.h : 1
    readonly property string fitClass: area && area.sized ? Fit.fitClass(gridW, gridH) : "small"

    // Place and size both come from the area's placement. While a corner is
    // being pulled the area lays the whole grid out at the wanted size, so the
    // cell under the hand and everything it pushes aside are previewed
    // together - the cell alone used to be previewed, and it could grow past
    // an edge the packer had already refused it and then teleport on release.
    x: cell ? cell.x : 0
    y: cell ? cell.y : 0
    width: cell ? cell.width : 0
    height: cell ? cell.height : 0

    // The neighbours glide to their new places; the item under the hand does
    // not animate. While it is dragged it is not even the thing on screen -
    // its ghost is, and that one follows the pointer directly - and while it
    // is sized, a glide would trail the corner being pulled.
    readonly property bool glides: Animations.motionEnabled && !item.dragging
        && !item.sizing && (!item.area || item.area.animated)
    Behavior on x {
        enabled: item.glides
        NumberAnimation { duration: Animations.reorder; easing.type: Animations.easing }
    }
    Behavior on y {
        enabled: item.glides
        NumberAnimation { duration: Animations.reorder; easing.type: Animations.easing }
    }
    Behavior on width {
        enabled: item.glides
        NumberAnimation { duration: Animations.reorder; easing.type: Animations.easing }
    }
    Behavior on height {
        enabled: item.glides
        NumberAnimation { duration: Animations.reorder; easing.type: Animations.easing }
    }

    onContentHeightChanged: if (area) area.reportHeight(itemId, contentHeight)
    Component.onCompleted: if (area) area.reportHeight(itemId, contentHeight)
    Component.onDestruction: {
        if (!area) return
        area.forgetHeight(itemId)
        // An item taken off the surface while its own corner is held would
        // leave the grid laid out for a size nobody is pulling any more.
        if (sizing) area.endSizing()
    }

    // The corner handle, above everything: pull it and the cell takes more
    // columns and rows. The grid follows while you pull and the size is handed
    // back once, on release - one write, one undo step, like a move.
    readonly property bool sizing: area !== null && area.sizingId === itemId

    Rectangle {
        id: handle
        // Inside the cell, not half outside it: the right-hand column's
        // handles sat on the panel's edge, which clips, and were cut in half.
        x: parent.width - width - Metrics.spaceXxs
        y: parent.height - height - Metrics.spaceXxs
        z: 4
        visible: item.resizable && item.area && item.area.editing && !item.dragging
        width: Metrics.iconSm
        height: width
        radius: width / 2
        // Accent and opaque. At 11.5 % white whatever was under it showed
        // through and in the light theme it vanished on a card; a solid
        // neutral read as a hole punched in the tile.
        color: item.sizing || resize.containsMouse ? Colors.accentHover : Colors.accent
        border.width: Metrics.borderWidth
        border.color: Colors.accent

        MouseArea {
            id: resize
            anchors.fill: parent
            anchors.margins: -Metrics.spaceXs
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SizeFDiagCursor
            property bool pulling: false
            // The cell as it was when the handle was pressed: the origin the
            // size is measured from, and the size a release is compared with.
            property var from: null
            // The handle sits inside the cell, so the pointer is up and left of
            // the corner it is supposed to be dragging - most of half a row at
            // the default step. The offset is taken once and carried, so the
            // first move does not snap the cell a row shorter.
            property real offsetX: 0
            property real offsetY: 0
            onPressed: mouse => {
                const cell = item.area.cellOf(item.itemId)
                if (!cell) return
                const point = mapToItem(item.area, mouse.x, mouse.y)
                from = cell
                offsetX = point.x - (cell.x + cell.width)
                offsetY = point.y - (cell.y + cell.height)
                pulling = true
                item.area.sizingW = cell.w
                item.area.sizingH = cell.h
                item.area.sizingId = item.itemId
            }
            onPositionChanged: mouse => {
                if (!pulling) return
                const point = mapToItem(item.area, mouse.x, mouse.y)
                const wanted = item.area.sizeAt(from, point.x - offsetX, point.y - offsetY)
                item.area.sizingW = wanted.w
                item.area.sizingH = wanted.h
            }
            onReleased: {
                if (!pulling) return
                pulling = false
                const w = item.area.sizingW
                const h = item.area.sizingH
                item.area.endSizing()
                // A press that never moved is not a resize. It used to write
                // the layout file and cost an undo step, unlike the drag, which
                // has always refused a drop on the item's own gap.
                if (from && (w !== from.w || h !== from.h)) item.resized(w, h)
            }
            onCanceled: {
                pulling = false
                item.area.endSizing()
            }
        }
    }

    // Above the item's own content, so the whole tile can be picked up rather
    // than only the gaps between its controls.
    MouseArea {
        id: drag
        anchors.fill: parent
        z: 2
        enabled: item.draggable && item.area && item.area.editing
        visible: enabled
        preventStealing: true
        cursorShape: item.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real pressX: 0
        property real pressY: 0
        property bool moved: false

        onPressed: mouse => {
            const point = mapToItem(item.area, mouse.x, mouse.y)
            pressX = point.x
            pressY = point.y
            moved = false
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            const point = mapToItem(item.area, mouse.x, mouse.y)
            if (!moved) {
                if (Math.abs(point.x - pressX) + Math.abs(point.y - pressY) < Metrics.dragThreshold) return
                // The grab point inside the item, so the ghost hangs where it
                // was taken hold of instead of jumping to its own centre.
                moved = item.area.begin(item.itemId, item, pressX - item.x, pressY - item.y)
                if (!moved) return
            }
            item.area.update(point.x, point.y)
        }
        onReleased: {
            if (moved) item.area.finish()
            moved = false
        }
        onCanceled: {
            if (moved) item.area.cancel()
            moved = false
        }
    }
}
