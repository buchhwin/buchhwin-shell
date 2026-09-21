import QtQuick
import qs.theme

// The small "i" that follows a name which has more to say. Rest the pointer on
// it and the explanation appears in a bubble; ignore it and nothing happens.
//
// It replaces the previous arrangement, where the explanation was a line of
// small print under the label that appeared while the *label* was hovered.
// That had two faults and the second is the one that was felt: nothing marked
// which labels had anything to say, so the only way to find out was to sweep
// the pointer along the column; and the line was a member of the layout, so
// every row below it jumped down the moment it appeared and back up when it
// went. A bubble is drawn on the overlay and moves nothing.
//
// Deliberately not a `ShellButton`: there is nothing to click. A button that
// does nothing on click is a worse lie than a mark that was never a button.
Item {
    id: root
    property string text: ""
    property int size: Metrics.iconXs

    implicitWidth: size
    implicitHeight: size
    // A name with nothing to explain has no mark after it.
    visible: root.text.length > 0

    ToolTipHost {
        id: tip
        anchorItem: root
        text: root.text
    }

    // The same handful the hover uses, exposed so a test can drive them: a
    // hover never registers in a nested session, so the only way this is held
    // to account at all is through the API. `arm` is also what the keyboard
    // path uses - `SettingRow` opens the bubble when the row's control takes
    // the focus, and it waits exactly as long as the pointer does, or tabbing
    // through a page of settings would flash a bubble on every row on the way
    // past.
    function findLayer() { return tip.findLayer() }
    function arm() { tip.arm() }
    function show() { tip.show() }
    function hide() { tip.release() }

    ShellIcon {
        id: glyph
        anchors.centerIn: parent
        glyph: Icons.info
        size: root.size
        // Quiet at rest: it is an offer, not an instruction. It brightens
        // under the pointer so that the wait before the bubble reads as
        // something happening rather than as nothing happening.
        color: hover.hovered ? Colors.text : Colors.mutedText
        opacity: hover.hovered ? 1 : Effects.mutedOpacity
        Behavior on opacity { NumberAnimation { duration: Animations.hover; easing.type: Animations.easing } }
    }

    // A HoverHandler rather than a MouseArea: this must not take a press away
    // from anything, and a MouseArea with `hoverEnabled` swallows the hover of
    // whatever sits under it.
    HoverHandler {
        id: hover
        cursorShape: Qt.WhatsThisCursor
        onHoveredChanged: hovered ? tip.arm() : tip.release()
    }

    onVisibleChanged: if (!visible) tip.release()
    onTextChanged: if (!text.length) tip.release()
}
