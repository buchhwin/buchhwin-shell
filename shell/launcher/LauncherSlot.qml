import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.editor

// One block of the launcher: the dashboard's `DashboardSlot` with the size
// handle, on a grid whose rows are a share of the card. The place comes from
// the `ArrangeArea`, not from a layout, so the blocks can glide aside to open
// a gap under the one being dragged.
ArrangeItem {
    id: slot
    required property string blockId
    required property string type
    required property string label
    required property int slotIndex
    // The search field and the result list may be moved and not removed:
    // without them it is not a launcher. They keep the wiggle - they *can* be
    // dragged - and lose only the badge.
    required property bool removable
    property Component content: null
    // Whether the block holds a row at all. A block with nothing to show - the
    // pinned row while something is typed - gives its row to the grid, and
    // the ones under it move up; the launcher says so per block.
    property bool holds: true

    itemId: blockId
    readonly property bool editing: area && area.editing

    draggable: true
    // Every block carries its own size in the grid, pulled from its corner
    // like a tile of the control center. The cell decides the height, so this
    // only says whether the block holds a place at all - and while arranging
    // it always does, or a block with nothing to show could not be grabbed and
    // its remove badge would be painted at the grid's origin instead, which is
    // what once put a red Remove on the search field.
    contentHeight: visible ? 1 : 0
    visible: holds

    Loader {
        id: body
        anchors.fill: parent
        sourceComponent: slot.content
        // A block that does not fit is cut off at its own edge rather than
        // painted over its neighbours.
        clip: true
        // Dimmed while the launcher is arranged: it cannot be operated then,
        // and the badge above it has to be legible against it.
        opacity: slot.editing ? Effects.mutedOpacity : 1
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
        // Only the content leans, so the badge is not a moving target.
        transform: Rotation {
            origin.x: body.width / 2
            origin.y: body.height / 2
            angle: wiggle.angle
        }
    }

    Wiggle {
        id: wiggle
        index: slot.slotIndex
        running: slot.editing && !slot.dragging
    }

    ShellButton {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Metrics.spaceXxs
        z: 3
        visible: slot.editing && slot.removable
        width: Metrics.controlHeightSm
        height: Metrics.controlHeightSm
        icon: Icons.remove
        iconSize: Math.round(Metrics.controlHeightSm / 2)
        variant: "danger"
        compact: true
        toolTip: "Remove " + slot.label
        onClicked: LayoutService.launcherRemove(slot.blockId)
    }
}
