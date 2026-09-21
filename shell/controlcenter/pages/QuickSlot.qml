import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.editor
import "../../../services/quick/QuickLogic.js" as Quick

// One tile of the control center, and everything editing it needs.
//
// The tiles keep their own files and their own conditions - a tile with
// nothing to show still hides itself. This only decides where a tile sits,
// whether it is there at all, and what it looks like while the panel is being
// arranged: it leans, it can be picked up, and it carries a button that takes
// it off the panel.
//
// The place comes from the ArrangeArea, not from a layout, so the tiles can
// glide aside to open a gap under the one being dragged.
ArrangeItem {
    id: slot
    required property string tileId
    required property string type
    required property int slotIndex
    property Component content: null

    itemId: tileId
    readonly property bool editing: area && area.editing
    readonly property bool shown: tile.item !== null && tile.item.shown === true

    draggable: true
    // The cell decides the size now; this only says whether the tile holds a
    // place at all. A tile with nothing to show does not - except while the
    // panel is being arranged, when every tile is on it, dimmed, or the
    // indices the drop maths produces would count a shorter list than the one
    // being moved. `visible` is exactly that rule already.
    contentHeight: visible ? 1 : 0
    onResized: (w, h) => LayoutService.quickSetSize(slot.tileId, w, h)
    // In edit mode every tile stays, so the panel does not jump about while it
    // is being arranged - a tile that has nothing to show is dimmed further.
    visible: shown || editing

    // The two controls sit on opposite corners, so they never meet however
    // short the cell is, and they shrink with it: a 30 px capsule fills a
    // one-row cell on its own.
    readonly property real chrome: Math.max(Metrics.iconSm,
        Math.min(Metrics.controlHeightSm, slot.height - Metrics.spaceXxs * 2))

    Loader {
        id: tile
        anchors.fill: parent
        sourceComponent: slot.content
        // The cell's shape, where the tile bodies can read it: a Component
        // declared at the root of another file sees the properties of the
        // Loader that created it, not of the item the Loader happens to sit
        // in. Putting these on the slot instead left every tile body reading
        // undefined.
        readonly property int gridW: slot.gridW
        readonly property int gridH: slot.gridH
        readonly property string fitClass: slot.fitClass
        // The type too, for the widget fallback.
        readonly property string tileType: slot.type
        // The cell decides the size and ShellCard does not clip, so a tile
        // that does not fit its cell painted over its neighbours instead of
        // being cut off at its own edge.
        clip: true
        // Dimmed while the panel is arranged: the tile cannot be operated then
        // - the drag surface covers all of it - and the controls above it have
        // to be legible against whatever the tile happens to be showing. One
        // that has nothing to show is dimmed further still.
        opacity: !slot.editing ? 1 : slot.shown ? Effects.mutedOpacity : Effects.disabledOpacity
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
        // Only the content leans. The lean used to sit on the item itself, so
        // the remove button and the corner handle rotated with the tile and a
        // 16 px handle was a moving target.
        transform: Rotation {
            origin.x: tile.width / 2
            origin.y: tile.height / 2
            angle: wiggle.angle
        }
    }

    Wiggle {
        id: wiggle
        index: slot.slotIndex
        // Nor while the tile is being sized: the size under the hand is the
        // thing being read, and a wobbling preview cannot be read.
        running: slot.editing && !slot.dragging && !slot.sizing
    }

    // Top left, opposite the corner handle, above the drag surface that covers
    // the whole tile. It lies on the tile's own icon, which is why the tile
    // below it is dimmed rather than left at full strength.
    ShellButton {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Metrics.spaceXxs
        z: 3
        visible: slot.editing
        width: slot.chrome
        height: slot.chrome
        icon: Icons.remove
        iconSize: Math.round(slot.chrome / 2)
        variant: "danger"
        compact: true
        toolTip: "Remove " + (Quick.isKnown(slot.type) ? Quick.label(slot.type)
            : WidgetRegistry.type(slot.type) ? WidgetRegistry.type(slot.type).label : slot.type)
        onClicked: LayoutService.quickRemove(slot.tileId)
    }
}
