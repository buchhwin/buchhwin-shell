import QtQuick
import qs.theme
import qs.services
import qs.shell.components
import qs.shell.editor
import "../../services/dashboard/DashboardLogic.js" as Dash

// One card of the dashboard, and everything editing it needs. The control
// center's QuickSlot with a different catalogue: the two surfaces are the same
// thing, so they behave the same way under the hand.
//
// The place comes from the ArrangeArea, not from a layout, so the cards can
// glide aside to open a gap under the one being dragged.
ArrangeItem {
    id: slot
    required property string cardId
    required property string type
    required property int slotIndex
    property Component content: null

    itemId: cardId
    readonly property bool editing: area && area.editing
    readonly property bool shown: card.item !== null && card.item.shown === true

    draggable: true
    // The cell decides the size; this only says whether the card holds a place
    // at all. One with nothing to show does not - except while the dashboard
    // is being arranged, when every card is on it, dimmed, or the indices the
    // drop maths produces would count a shorter list than the one being moved.
    contentHeight: visible ? 1 : 0
    onResized: (w, h) => LayoutService.dashboardSetSize(slot.cardId, w, h)
    visible: shown || editing

    // Both controls on opposite corners, sized down with the cell.
    readonly property real chrome: Math.max(Metrics.iconSm,
        Math.min(Metrics.controlHeightSm, slot.height - Metrics.spaceXxs * 2))

    Loader {
        id: card
        anchors.fill: parent
        sourceComponent: slot.content
        // The cell's shape, where the card bodies can read it: a Component
        // declared at the root of another file sees the properties of the
        // Loader that created it, not of the item the Loader happens to sit
        // in. Putting these on the slot instead left every card body reading
        // undefined.
        readonly property int gridW: slot.gridW
        readonly property int gridH: slot.gridH
        readonly property string fitClass: slot.fitClass
        // The type too, for the widget fallback.
        readonly property string tileType: slot.type
        // A card that does not fit its cell is cut off at its own edge rather
        // than painted over its neighbours.
        clip: true
        // Dimmed while the dashboard is arranged: it cannot be operated then,
        // and the controls above it have to be legible against it.
        opacity: !slot.editing ? 1 : slot.shown ? Effects.mutedOpacity : Effects.disabledOpacity
        Behavior on opacity {
            NumberAnimation { duration: Animations.hover; easing.type: Animations.easing }
        }
        // Only the content leans, so the controls are not moving targets.
        transform: Rotation {
            origin.x: card.width / 2
            origin.y: card.height / 2
            angle: wiggle.angle
        }
    }

    Wiggle {
        id: wiggle
        index: slot.slotIndex
        running: slot.editing && !slot.dragging && !slot.sizing
    }

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
        toolTip: "Remove " + (Dash.isKnown(slot.type) ? Dash.label(slot.type)
            : WidgetRegistry.type(slot.type) ? WidgetRegistry.type(slot.type).label : slot.type)
        onClicked: LayoutService.dashboardRemove(slot.cardId)
    }
}
