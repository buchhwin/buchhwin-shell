import QtQuick
import qs.theme
import qs.shell.components

// One item of the lock screen's grid. The dashboard's slot without its
// editing chrome: the lock screen is arranged in Settings, on a preview, so
// the real one never drags, never resizes and never shows a remove button.
// Editing a surface whose whole job is to be modal is a trap, and two
// full-screen surfaces with the keyboard at once is worse than a trap.
ArrangeItem {
    id: slot
    required property string blockId
    required property string type
    property Component content: null

    itemId: blockId
    draggable: false
    resizable: false
    contentHeight: 1

    Loader {
        anchors.fill: parent
        sourceComponent: slot.content
        // The cell's shape, where the blocks can read it: a Component sees
        // the properties of the Loader that created it.
        readonly property int gridW: slot.gridW
        readonly property int gridH: slot.gridH
        readonly property string fitClass: slot.fitClass
        // The safety net, not the mechanism - the blocks draw for their cell.
        clip: true
    }
}
